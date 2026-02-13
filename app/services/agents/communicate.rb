# frozen_string_literal: true

module Agents
  class Communicate
    def self.call(from_agent:, content:, team:, to_agent: nil)
      new(from_agent:, content:, team:, to_agent:).call
    end

    def initialize(from_agent:, content:, team:, to_agent: nil)
      @from_agent = from_agent
      @content = content
      @team = team
      @to_agent = to_agent
    end

    def call
      return ServiceResponse.failure(error: "Agent must be on the specified team") unless agent_on_team?

      message = create_team_message

      if message.persisted?
        broadcast_message(message)
        ServiceResponse.success(data: { message: })
      else
        ServiceResponse.failure(error: message.errors.full_messages)
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Communication failed: #{e.message}")
    end

    private

    def agent_on_team?
      @from_agent.team_id == @team.id
    end

    def create_team_message
      TeamMessage.create(
        team_id: @team.id,
        from_agent_id: @from_agent.id,
        to_agent_id: @to_agent&.id,
        message_type: @to_agent ? "direct" : "broadcast",
        content: @content
      )
    end

    def broadcast_message(message)
      ActionCable.server.broadcast(
        "team_#{@team.id}",
        {
          type: "team_message",
          message: {
            id: message.id,
            from_agent: {
              id: @from_agent.id,
              name: @from_agent.name,
              role: @from_agent.role
            },
            to_agent: @to_agent ? {
              id: @to_agent.id,
              name: @to_agent.name
            } : nil,
            content: @content,
            message_type: message.message_type,
            created_at: message.created_at.iso8601
          }
        }
      )
    end
  end
end
