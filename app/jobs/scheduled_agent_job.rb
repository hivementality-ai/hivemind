# frozen_string_literal: true

class ScheduledAgentJob < ApplicationJob
  queue_as :default

  # Runs a scheduled task by sending a prompt to the agent
  # @param scheduled_task_id [Integer] The ScheduledTask record ID
  def perform(scheduled_task_id)
    task = ScheduledTask.find_by(id: scheduled_task_id)
    return unless task&.enabled?

    agent = task.agent
    return unless agent

    prompt = task.job_params&.dig("prompt") || task.description || "Run scheduled task: #{task.name}"

    # Create a new conversation for this scheduled run
    session = agent.sessions.create!(
      title: "Scheduled: #{task.name}",
      session_type: "scheduled"
    )

    # Enqueue the chat
    ChatStreamJob.perform_later(
      session_id: session.id,
      agent_id: agent.id,
      message: prompt
    )

    # Update task tracking
    task.update!(
      last_run_at: Time.current,
      next_run_at: calculate_next_run(task.schedule)
    )
  rescue StandardError => e
    task&.update(last_error_at: Time.current) if task
    Rails.logger.error("ScheduledAgentJob failed for task #{scheduled_task_id}: #{e.message}")
  end

  private

  def calculate_next_run(cron_expression)
    Fugit::Cron.parse(cron_expression)&.next_time&.to_t
  rescue StandardError
    nil
  end
end
