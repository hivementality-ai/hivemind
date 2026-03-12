# frozen_string_literal: true

module TeamChats
  class Export
    MAX_TOOL_OUTPUT_SIZE = 10_240 # 10KB

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
        team_chat: team_chat_metadata,
        team: team_info,
        agents: agents_info,
        usage: usage_stats,
        timeline: merged_timeline,
        tool_executions_summary: tool_executions_summary
      }
    end

    def team_chat_metadata
      {
        id: session.id,
        session_key: session.session_key,
        title: session.title,
        status: session.status,
        created_at: session.created_at&.iso8601,
        updated_at: session.updated_at&.iso8601,
        message_count: session.team_chat_messages.count,
        agent_session_count: session.agent_sessions.count
      }
    end

    def team_info
      team = session.team
      {
        id: team.id,
        name: team.name,
        description: team.description
      }
    end

    def agents_info
      session.agent_sessions.includes(:agent).map do |agent_session|
        agent = agent_session.agent
        {
          id: agent.id,
          name: agent.name,
          slug: agent.slug,
          role: agent.role,
          llm_model: agent.llm_model,
          session_id: agent_session.id,
          tokens: {
            input: agent_session.input_tokens,
            output: agent_session.output_tokens,
            total: agent_session.total_tokens
          }
        }
      end
    end

    def usage_stats
      agent_sessions = session.agent_sessions
      {
        total_messages: session.team_chat_messages.count,
        total_agent_sessions: agent_sessions.count,
        total_input_tokens: agent_sessions.sum(:input_tokens),
        total_output_tokens: agent_sessions.sum(:output_tokens),
        total_tokens: agent_sessions.sum(:total_tokens),
        total_tool_executions: ToolExecution.where(session: agent_sessions).count
      }
    end

    def merged_timeline
      entries = []

      # Add team chat messages
      session.team_chat_messages.includes(:target_agent).order(:created_at).each do |msg|
        entries << {
          type: "team_message",
          timestamp: msg.created_at.iso8601,
          sender_type: msg.sender_type,
          sender_id: msg.sender_id,
          sender_name: resolve_sender_name(msg),
          target_agent: msg.target_agent&.name,
          content: msg.content
        }.compact
      end

      # Add agent sub-session transcripts and tool executions
      session.agent_sessions.includes(:agent, tool_executions: :tool).each do |agent_session|
        agent_name = agent_session.agent.name

        (agent_session.transcript || []).each do |entry|
          entries << {
            type: "agent_message",
            timestamp: entry["timestamp"],
            agent: agent_name,
            agent_session_id: agent_session.id,
            role: entry["role"],
            content: entry["content"],
            source: entry["source"],
            tool_call: entry["tool_call"],
            tool_result: entry["tool_result"]
          }.compact
        end

        agent_session.tool_executions.each do |te|
          entries << {
            type: "tool_execution",
            timestamp: te.created_at.iso8601,
            agent: agent_name,
            agent_session_id: agent_session.id,
            tool_name: te.tool.name,
            status: te.status,
            input: te.input,
            output: truncate_output(te.output),
            error: te.error,
            exit_code: te.exit_code,
            duration_ms: te.duration_ms
          }.compact
        end
      end

      entries.sort_by { |e| e[:timestamp] || "" }
    end

    def tool_executions_summary
      all_executions = ToolExecution.where(session: session.agent_sessions).includes(:tool, :agent)

      all_executions.group_by { |te| te.tool.name }.transform_values do |executions|
        {
          count: executions.size,
          statuses: executions.group_by(&:status).transform_values(&:size),
          total_duration_ms: executions.sum { |te| te.duration_ms || 0 },
          agents: executions.map { |te| te.agent.name }.uniq
        }
      end
    end

    def resolve_sender_name(msg)
      if msg.from_user?
        User.find_by(id: msg.sender_id)&.email || "User ##{msg.sender_id}"
      else
        Agent.find_by(id: msg.sender_id)&.name || "Agent ##{msg.sender_id}"
      end
    end

    def truncate_output(output)
      return nil unless output
      return output if output.bytesize <= MAX_TOOL_OUTPUT_SIZE

      output.byteslice(0, MAX_TOOL_OUTPUT_SIZE) + "\n... [truncated at #{MAX_TOOL_OUTPUT_SIZE} bytes]"
    end
  end
end
