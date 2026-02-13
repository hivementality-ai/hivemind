# frozen_string_literal: true

class AgentTaskJob
  include Sidekiq::Job

  sidekiq_options queue: :agent_tasks, retry: 3

  def perform(agent_id, team_message_id)
    agent = Agent.find(agent_id)
    message = TeamMessage.find(team_message_id)

    # Create a new session for the delegated task
    session = Session.create!(
      key: "task_#{SecureRandom.uuid}",
      agent_id: agent.id,
      metadata: {
        source: "delegation",
        team_message_id: message.id,
        from_agent_id: message.from_agent_id,
        task: message.content
      },
      transcript: []
    )

    # Update message status
    message.update(status: "processing")

    # Execute the agent task
    # This would integrate with your agent runtime
    # For now, we'll log the task execution
    Rails.logger.info("Agent #{agent.name} processing task: #{message.content}")

    # Mark as completed
    message.update(status: "completed", completed_at: Time.current)

    # Broadcast completion
    ActionCable.server.broadcast(
      "team_#{message.team_id}",
      {
        type: "task_completed",
        message_id: message.id,
        agent_id: agent.id
      }
    )
  rescue StandardError => e
    Rails.logger.error("AgentTaskJob failed: #{e.message}")
    message&.update(status: "failed", metadata: message.metadata.merge(error: e.message))
    raise
  end
end
