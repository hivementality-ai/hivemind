# frozen_string_literal: true

class ScheduledAgentJob < ApplicationJob
  queue_as :agents

  # Runs a scheduled task by sending a prompt to the agent
  # @param scheduled_task_id [Integer] The ScheduledTask record ID
  def perform(scheduled_task_id)
    task = ScheduledTask.find_by(id: scheduled_task_id)
    return unless task&.enabled?

    agent = task.agent
    return unless agent

    prompt = task.job_params&.dig("prompt") || task.description || "Run scheduled task: #{task.name}"

    if task.precheck_url.present?
      check = ScheduledTasks::Precheck.call(task)
      if check.status == :unchanged
        task.update!(last_checked_at: Time.current, last_check_result: "unchanged", next_run_at: calculate_next_run(task.schedule))
        return
      end
      prompt = with_new_items(prompt, check.items)
      task.update!(precheck_state: check.state) if check.state
      task.assign_attributes(last_checked_at: Time.current, last_check_result: check.status.to_s)
    end

    # Create a new conversation for this scheduled run
    session = agent.sessions.create!(
      session_key: "scheduled-#{task.id}-#{SecureRandom.hex(4)}",
      title: "Scheduled: #{task.name}",
      metadata: { type: "scheduled", scheduled_task_id: task.id }
    )

    # Enqueue the chat
    ChatStreamJob.perform_later(session.id, prompt)

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

  def with_new_items(prompt, items)
    return prompt if items.empty?

    lines = items.map { |item| "- #{item[:title]} #{item[:link]}".strip }
    "#{prompt}\n\nNew since the last check:\n#{lines.join("\n")}"
  end

  def calculate_next_run(cron_expression)
    Fugit::Cron.parse(cron_expression)&.next_time&.to_t
  rescue StandardError
    nil
  end
end
