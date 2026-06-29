# frozen_string_literal: true

module Sessions
  class Export
    include ToolOutputTruncation

    def self.call(session:)
      new(session:).call
    end

    def initialize(session:)
      @session = session
    end

    def call
      ServiceResponse.success(data: { export: build_export })
    rescue StandardError => e
      ServiceResponse.failure(error: "Export failed: #{e.message}")
    end

    private

    attr_reader :session

    def build_export
      {
        version: "1.0",
        exported_at: Time.current.iso8601,
        session: session_metadata,
        agent: agent_info,
        usage: usage_stats,
        conversation_summary: session.conversation_summary,
        timeline: merged_timeline,
        tool_executions_summary: tool_executions_summary
      }
    end

    def session_metadata
      {
        id: session.id,
        session_key: session.session_key,
        title: session.title,
        status: session.status,
        created_at: session.created_at&.iso8601,
        last_activity_at: session.last_activity_at&.iso8601,
        origin_channel_type: session.origin_channel_type,
        origin_sender: session.origin_sender,
        metadata: session.metadata
      }
    end

    def agent_info
      agent = session.agent
      {
        id: agent.id,
        name: agent.name,
        slug: agent.slug,
        role: agent.role,
        llm_model: agent.llm_model,
        model_provider: agent.model_provider
      }
    end

    def usage_stats
      {
        input_tokens: session.input_tokens,
        output_tokens: session.output_tokens,
        total_tokens: session.total_tokens,
        transcript_entries: session.transcript_size,
        tool_executions_count: session.tool_executions.count
      }
    end

    def merged_timeline
      entries = []

      # Add transcript entries
      (session.transcript || []).each do |entry|
        entries << {
          type: "message",
          timestamp: entry["timestamp"],
          role: entry["role"],
          content: entry["content"],
          source: entry["source"],
          tool_call: entry["tool_call"],
          tool_result: entry["tool_result"]
        }.compact
      end

      # Add tool executions
      session.tool_executions.includes(:tool).find_each do |te|
        entries << {
          type: "tool_execution",
          timestamp: te.created_at.iso8601,
          tool_name: te.tool.name,
          status: te.status,
          input: te.input,
          output: truncate_output(te.output),
          error: te.error,
          exit_code: te.exit_code,
          duration_ms: te.duration_ms
        }.compact
      end

      # Sort by timestamp
      entries.sort_by { |e| e[:timestamp] || "" }
    end

    def tool_executions_summary
      session.tool_executions.includes(:tool).group_by { |te| te.tool.name }.transform_values do |executions|
        {
          count: executions.size,
          statuses: executions.group_by(&:status).transform_values(&:size),
          total_duration_ms: executions.sum { |te| te.duration_ms || 0 }
        }
      end
    end
  end
end
