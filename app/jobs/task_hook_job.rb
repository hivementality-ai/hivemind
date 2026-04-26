# frozen_string_literal: true

# DEPRECATED: This job is superseded by the 3-phase pipeline:
#   Tasks::PreTransitionJob → Tasks::TransitionJob → Tasks::PostTransitionJob
#
# Kept for backward compatibility. If called directly, it delegates to
# PostTransitionJob since the old behavior was post-hook execution only.
class TaskHookJob < ApplicationJob
  queue_as :system

  def perform(task_id, status, trigger, agent_id, context_json)
    Rails.logger.info("[TaskHookJob] DEPRECATED: routing to new pipeline jobs")

    case trigger
    when "pre"
      Tasks::PreTransitionJob.perform_later(task_id, status, agent_id, context_json)
    when "post"
      Tasks::PostTransitionJob.perform_later(task_id, status, agent_id, context_json)
    else
      Rails.logger.warn("[TaskHookJob] Unknown trigger '#{trigger}', ignoring")
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn("[TaskHookJob] Record not found: #{e.message}")
  end
end
