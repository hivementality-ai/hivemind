# frozen_string_literal: true

module HashtagActions
  module Actions
    class Status < Base
      def execute
        transcript = session.transcript || []
        memories_count = MemoryEntry.where(agent: agent).count
        tools_count = agent.agent_tools.count
        tools_count = Tool.enabled.builtin.count if tools_count.zero?

        usage = UsageRecord.where(agent: agent)
        total_cost = usage.sum(:cost_cents)
        total_tokens = usage.sum(:input_tokens) + usage.sum(:output_tokens)

        lines = [
          "Agent: #{agent.name} (#{agent.role || 'assistant'})",
          "Model: #{agent.llm_model} via #{agent.model_provider}",
          "Session: #{transcript.size} messages",
          "Memories: #{memories_count}",
          "Tools: #{tools_count}",
          "Usage: #{total_tokens.to_fs(:delimited)} tokens ($#{'%.4f' % (total_cost / 100.0)})",
          "Team: #{agent.team&.name || 'none'}"
        ]

        { response: lines.join("\n"), status: "ok" }
      end
    end
  end
end
