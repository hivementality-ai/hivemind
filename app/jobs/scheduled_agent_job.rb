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
      task.precheck_state = check.state if check.state
      closed = task.hold_closed?
      task.hold(check.items, extra: check.extra, page_changed: check.items.empty?) if check.status == :changed

      if check.status != :failed && (!task.holding? || closed)
        task.update!(precheck_state: task.precheck_state, held_changes: task.held_changes,
                     last_checked_at: Time.current, last_check_result: task.holding? ? "held" : "unchanged",
                     next_run_at: calculate_next_run(task.schedule))
        return
      end

      released = task.release_held
      prompt = with_new_items(prompt, released["items"], released["extra"])
      task.update!(precheck_state: task.precheck_state, held_changes: task.held_changes)
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

  def with_new_items(prompt, items, extra = 0)
    return prompt if items.empty?

    lines = items.map { |item| "- #{item['title']} #{item['link']}".strip }
    lines << "...and #{extra} more not listed" if extra.positive?
    "#{prompt}\n\nNew since the last check:\n#{lines.join("\n")}"
  end

  def calculate_next_run(cron_expression)
    Fugit::Cron.parse(cron_expression)&.next_time&.to_t
  rescue StandardError
    nil
  end
end
