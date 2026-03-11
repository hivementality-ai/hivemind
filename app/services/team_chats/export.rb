# frozen_string_literal: true

module TeamChats
  class Export
    def self.call(team_chat_session:)
      new(team_chat_session:).call
    end

    def initialize(team_chat_session:)
      @tcs = team_chat_session
    end

    def call
      team = @tcs.team
      messages = @tcs.team_chat_messages.chronological
      agent_sessions = @tcs.agent_sessions.includes(:agent)

      all_tool_execs = ToolExecution.where(session: agent_sessions)
                                     .includes(:tool, :agent)
                                     .order(:created_at)

      {
        export_type: "team_chat",
        exported_at: Time.current.iso8601,
        hivemind_version: Hivemind::VERSION,

        team_chat_session: {
          id: @tcs.id,
          session_key: @tcs.session_key,
          title: @tcs.title,
          status: @tcs.status,
          created_at: @tcs.created_at.iso8601
        },

        team: {
          id: team.id,
          name: team.name
        },

        agents: team.agents.order(:name).map { |a|
          { id: a.id, name: a.name, role: a.role, model: a.llm_model }
        },

        timeline: build_team_timeline(messages, agent_sessions, all_tool_execs),

        agent_sessions: agent_sessions.map { |s|
          agent = s.agent
          execs = all_tool_execs.select { |te| te.session_id == s.id }
          {
            agent_id: agent.id,
            agent_name: agent.name,
            session_id: s.id,
            transcript_length: s.transcript_size,
            tool_calls: execs.size,
            tokens: {
              input: s.input_tokens || 0,
              output: s.output_tokens || 0
            }
          }
        },

        tool_executions_summary: build_team_tool_summary(all_tool_execs)
      }
    end

    private

    def build_team_timeline(messages, agent_sessions, tool_execs)
      entries = []

      messages.each do |msg|
        sender = msg.sender
        entry = {
          timestamp: msg.created_at.iso8601,
          type: msg.from_user? ? "user_message" : "agent_message",
          sender: msg.sender_type,
          sender_name: sender&.respond_to?(:name) ? sender.name : "Unknown",
          content: msg.content
        }

        if msg.from_agent?
          entry[:agent_id] = msg.sender_id
          agent_session = agent_sessions.find { |s| s.agent_id == msg.sender_id }
          entry[:agent_session_id] = agent_session&.id
        end

        entries << entry.compact
      end

      tool_execs.each do |te|
        agent = te.agent
        entries << {
          timestamp: te.created_at.iso8601,
          type: "tool_call",
          agent_name: agent&.name,
          agent_id: agent&.id,
          agent_session_id: te.session_id,
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

      entries.sort_by! { |e| e[:timestamp] }
      entries.each_with_index { |e, i| e[:index] = i }
      entries
    end

    def build_team_tool_summary(tool_execs)
      by_agent = tool_execs.group_by { |te| te.agent&.name || "unknown" }
      by_tool = tool_execs.group_by { |te| te.tool&.name || "unknown" }

      {
        total: tool_execs.size,
        by_agent: by_agent.transform_values { |execs|
          { count: execs.size, success: execs.count { |e| e.status == "completed" }, failed: execs.count { |e| e.status == "failed" } }
        },
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
