# frozen_string_literal: true

module Agents
  class Orchestrate
    def self.call(agent:, task:, team:)
      new(agent:, task:, team:).call
    end

    def initialize(agent:, task:, team:)
      @agent = agent
      @task = task
      @team = team
    end

    def call
      return ServiceResponse.failure(error: "Agent must be on the specified team") unless agent_on_team?

      subtasks = decompose_task
      delegations = []

      subtasks.each do |subtask|
        target_agent = find_best_agent(subtask[:role])
        next unless target_agent

        delegation = Agents::Delegate.call(
          from_agent: @agent,
          to_agent: target_agent,
          task: subtask[:description],
          context: { orchestration_id: generate_orchestration_id, parent_task: @task }
        )

        delegations << delegation.data if delegation.success?
      end

      if delegations.any?
        ServiceResponse.success(data: {
          orchestration_id: generate_orchestration_id,
          task: @task,
          delegations:,
          plan: subtasks
        })
      else
        ServiceResponse.failure(error: "No suitable agents found for task delegation")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Orchestration failed: #{e.message}")
    end

    private

    def agent_on_team?
      @agent.team_id == @team.id
    end

    def decompose_task
      # Simple role-based task decomposition
      # In production, this could use LLM to intelligently break down tasks
      [
        { role: "coder", description: "Implement code for: #{@task}" },
        { role: "researcher", description: "Research requirements for: #{@task}" },
        { role: "writer", description: "Document: #{@task}" }
      ].select { |subtask| role_needed?(subtask[:role]) }
    end

    def role_needed?(role)
      # Basic heuristic - could be enhanced with LLM analysis
      case role
      when "coder"
        @task.match?(/code|implement|build|develop|fix/i)
      when "researcher"
        @task.match?(/research|find|investigate|analyze/i)
      when "writer"
        @task.match?(/document|write|explain|describe/i)
      else
        false
      end
    end

    def find_best_agent(role)
      @team.agents.where(role:).where.not(id: @agent.id).first
    end

    def generate_orchestration_id
      @orchestration_id ||= SecureRandom.uuid
    end
  end
end
