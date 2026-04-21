# frozen_string_literal: true

module Tasks
  class TransitionJob < ApplicationJob
    queue_as :default

    # Performs the actual status change. Called after pre-hooks complete.
    # Fires PostTransitionJob after the status change.
    def perform(task_id, new_status, triggering_agent_id, context_json)
      task = Task.find(task_id)
      agent = triggering_agent_id ? Agent.find_by(id: triggering_agent_id) : nil
      context = JSON.parse(context_json)

      # Safety: task must be locked before we transition
      unless task.transition_locked?
        Rails.logger.warn("[TransitionJob] Task ##{task_id} is not locked — skipping transition")
        return
      end

      # Validate the transition is still valid
      unless Task::STATUSES.include?(new_status)
        fail_pipeline(task, "Invalid status '#{new_status}'")
        return
      end

      if task.status == new_status
        # Already at target status (maybe a pre-hook moved it?) — just unlock and stop
        task.unlock_transition!
        broadcast_pipeline_status(task, "transition", "skipped")
        return
      end

      # Check dependencies for forward transitions
      forward_statuses = %w[in_progress review done]
      if forward_statuses.include?(new_status) && task.blocked_by_dependencies?
        blockers = task.blocking_tasks.where.not(status: "done").pluck(:id, :title)
        blocker_list = blockers.map { |id, title| "##{id} #{title}" }.join(", ")
        fail_pipeline(task, "Blocked by incomplete dependencies: #{blocker_list}")
        return
      end

      # Perform the actual status change
      old_status = task.status
      task.status = new_status
      task.save!

      broadcast_pipeline_status(task, "transition", "completed")

      # Log the transition event
      Tasks::EventLogger.call(
        task: task,
        agent: agent,
        event_type: "status_change",
        summary: "Status changed from '#{old_status}' to '#{new_status}'",
        metadata: { from: old_status, to: new_status }
      )

      # Fire post-hooks
      Tasks::PostTransitionJob.perform_later(task_id, new_status, triggering_agent_id, context_json)

    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn("[TransitionJob] Record not found: #{e.message}")
    rescue ActiveRecord::RecordInvalid => e
      fail_pipeline(task, e.message) if task
      Rails.logger.error("[TransitionJob] Validation error: #{e.message}")
    rescue => e
      fail_pipeline(task, e.message) if task
      Rails.logger.error("[TransitionJob] Error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    end

    private

    def fail_pipeline(task, reason)
      task.unlock_transition!
      broadcast_pipeline_status(task, "transition", "failed", error: reason)
      Tasks::EventLogger.call(
        task: task,
        agent: nil,
        event_type: "pipeline_failed",
        summary: "Transition pipeline failed: #{reason}",
        metadata: { phase: "transition", error: reason }
      )
    end

    def broadcast_pipeline_status(task, phase, status, error: nil)
      ActionCable.server.broadcast("task_#{task.id}", {
        type: "pipeline_status",
        phase: phase,
        status: status,
        task_id: task.id,
        error: error
      }.compact)
    end
  end
end
