# frozen_string_literal: true

module Agents
  class Delegate
    def self.call(from_agent:, to_agent:, task:, context: nil)
      new(from_agent:, to_agent:, task:, context:).call
    end

    def initialize(from_agent:, to_agent:, task:, context: nil)
      @from_agent = from_agent
      @to_agent = to_agent
      @task = task
      @context = context
    end

    def call
      return ServiceResponse.failure(error: "Agent cannot delegate to itself") if @from_agent.id == @to_agent.id
      return ServiceResponse.failure(error: "Agents must be on the same team") unless same_team?

      message = create_team_message

      if message.persisted?
        enqueue_task(message)
        ServiceResponse.success(data: { message:, task: @task })
      else
        ServiceResponse.failure(error: message.errors.full_messages)
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Delegation failed: #{e.message}")
    end

    private

    def same_team?
      @from_agent.team_id.present? && @from_agent.team_id == @to_agent.team_id
    end

    def create_team_message
      TeamMessage.create(
        team_id: @from_agent.team_id,
        from_agent_id: @from_agent.id,
        to_agent_id: @to_agent.id,
        message_type: "delegation",
        content: @task,
        metadata: { context: @context }.compact
      )
    end

    def enqueue_task(message)
      AgentTaskJob.perform_async(@to_agent.id, message.id)
    end
  end
end
