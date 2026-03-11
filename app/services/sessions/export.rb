# frozen_string_literal: true

module Sessions
  class Export
    def self.call(session:)
      new(session:).call
    end

    def initialize(session:)
      @session = session
    end

    def call
      agent = @session.agent
      tool_executions = @session.tool_executions.includes(:tool).order(:created_at)

      timeline = build_timeline(tool_executions)
      tool_summary = build_tool_summary(tool_executions)

      cost = CostEstimator.estimate(
        model: agent.llm_model,
        input_tokens: @session.input_tokens || 0,
        output_tokens: @session.output_tokens || 0
      )

      {
        export_type: "session",
        exported_at: Time.current.iso8601,
        hivemind_version: Hivemind::VERSION,

        session: {
          id: @session.id,
          session_key: @session.session_key,
          title: @session.title,
          status: @session.status,
          created_at: @session.created_at.iso8601,
          last_activity_at: @session.last_activity_at&.iso8601,
          origin: {
            channel_type: @session.origin_channel_type,
            sender: @session.origin_sender
          }.compact.presence
        }.compact,

        agent: {
          id: agent.id,
          name: agent.name,
          slug: agent.slug,
          role: agent.role,
          model: agent.llm_model,
          provider: agent.model_provider
        },

        usage: {
          input_tokens: @session.input_tokens || 0,
          output_tokens: @session.output_tokens || 0,
          total_tokens: @session.total_tokens || 0,
          estimated_cost_cents: cost
        },

        conversation_summary: @session.conversation_summary,

        timeline: timeline,

        tool_executions_summary: tool_summary
      }.compact
    end

    private

    def build_timeline(tool_executions)
      entries = []
      tool_exec_queue = tool_executions.to_a.dup

      (@session.transcript || []).each do |msg|
        role = msg["role"] || msg[:role]
        content = msg["content"] || msg[:content]
        timestamp = msg["timestamp"] || msg[:timestamp]

        if role == "tool"
          tool_name = msg["tool_name"] || msg[:tool_name]

          matching_exec = tool_exec_queue.find { |te|
            te.tool&.name == tool_name && te.created_at.iso8601 <= timestamp.to_s
          }

          if matching_exec
            tool_exec_queue.delete(matching_exec)
            entries << build_tool_entry(matching_exec, timestamp:)
          else
            entries << {
              index: 0,
              timestamp: timestamp,
              role: "tool_result",
              tool_name: tool_name,
              content: content.to_s.truncate(10_000)
            }.compact
          end
        else
          entry = {
            index: 0,
            timestamp: timestamp,
            role: role,
            content: content
          }
          entry[:thinking] = msg["thinking"] || msg[:thinking] if role == "assistant"
          entries << entry.compact
        end
      end

      # Append unmatched tool executions
      tool_exec_queue.each do |te|
        entries << build_tool_entry(te)
      end

      entries.sort_by! { |e| e[:timestamp].to_s }
      entries.each_with_index { |e, i| e[:index] = i }
      entries
    end

    def build_tool_entry(te, timestamp: nil)
      {
        index: 0,
        timestamp: timestamp || te.created_at.iso8601,
        role: "tool_call",
        tool: te.tool&.name,
        tool_input: te.input,
        tool_output: te.output.to_s.truncate(10_000),
        tool_status: te.status,
        tool_exit_code: te.exit_code,
        tool_duration_ms: te.duration_ms,
        tool_error: te.error,
        tool_execution_id: te.id
      }.compact
    end

    def build_tool_summary(tool_executions)
      by_tool = tool_executions.group_by { |te| te.tool&.name || "unknown" }

      {
        total: tool_executions.size,
        by_tool: by_tool.transform_values { |execs|
          {
            count: execs.size,
            success: execs.count { |e| e.status == "completed" },
            failed: execs.count { |e| e.status == "failed" },
            avg_duration_ms: execs.filter_map(&:duration_ms).then { |d| d.any? ? (d.sum / d.size) : nil }
          }.compact
        }
      }
    end
  end
end
