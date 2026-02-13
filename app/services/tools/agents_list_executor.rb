# frozen_string_literal: true

module Tools
  class AgentsListExecutor < BaseExecutor
    def call
      agents = Agent.visible.enabled.includes(:team).order(:name)

      if agents.any?
        output = agents.map do |a|
          team = a.team&.name
          tools_count = a.agent_tools.count
          line = "• #{a.name} (#{a.role}) — #{a.llm_model}"
          line += " [Team: #{team}]" if team
          line += " [#{tools_count} tools]" if tools_count > 0
          line
        end.join("\n")

        ServiceResponse.success(data: {
          output: "Available agents (#{agents.size}):\n#{output}",
          exit_code: 0
        })
      else
        ServiceResponse.success(data: { output: "No agents available.", exit_code: 0 })
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Agents list failed: #{e.message}")
    end
  end
end
