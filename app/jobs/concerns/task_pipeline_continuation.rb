# frozen_string_literal: true

# Handles continuation of the task hook pipeline after a ChatStreamJob completes.
# When a session is part of a task hook pipeline (pre or post), this module
# detects completion and fires the next step in the chain.
module TaskPipelineContinuation
  extend ActiveSupport::Concern

  private

  # Call this at the end of ChatStreamJob (in ensure block) to check if
  # the session is part of a task hook pipeline and needs to continue.
  def continue_task_pipeline_if_needed(session)
    return unless session
    return unless session.metadata&.dig("type") == "task_hook_pipeline"

    pipeline = session.metadata["pipeline"]
    return unless pipeline

    task = Task.find_by(id: pipeline["task_id"])
    return unless task

    phase = pipeline["phase"]
    hook_ids = pipeline["hook_ids"] || []
    current_index = pipeline["current_hook_index"] || 0
    next_index = current_index + 1

    if next_index < hook_ids.length
      # More hooks in this phase — fire the next one
      advance_to_next_hook(task, pipeline, next_index)
    else
      # All hooks in this phase are done — move to next phase
      advance_to_next_phase(task, pipeline)
    end
  rescue => e
    Rails.logger.error("[TaskPipelineContinuation] Error: #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}")
    # Try to unlock on failure so the task isn't stuck
    if pipeline && (task = Task.find_by(id: pipeline["task_id"]))
      task.unlock_transition! if task.transition_locked?
    end
  end

  def advance_to_next_hook(task, pipeline, next_index)
    hook = TaskHook.find_by(id: pipeline["hook_ids"][next_index])
    return advance_to_next_phase(task, pipeline) unless hook

    phase = pipeline["phase"]
    context = JSON.parse(pipeline["context_json"])

    # Reload task to get latest assignment state
    task.reload
    fallback_agent = pipeline["triggering_agent_id"] ? Agent.find_by(id: pipeline["triggering_agent_id"]) : nil
    resolved_agent = hook.agent || task.assigned_to_agent || fallback_agent || task.created_by_agent

    unless resolved_agent
      # Can't resolve agent — skip this hook, try next
      pipeline["current_hook_index"] = next_index
      advance_to_next_hook(task, pipeline, next_index + 1)
      return
    end

    # Reassign if hook specifies an agent
    if hook.agent && task.assigned_to_agent != hook.agent
      task.update!(assigned_to_agent: hook.agent)
      Tasks::EventLogger.call(
        task: task,
        agent: hook.agent,
        event_type: "auto_assigned",
        summary: "Auto-assigned to #{hook.agent.name} by #{phase}-hook on '#{pipeline['new_status']}'"
      )
    end

    skill = hook.skill
    prompt = Tasks::HookExecutor.new(
      hook: hook, task: task, agent: resolved_agent, context: context
    ).build_prompt(skill)

    updated_pipeline = pipeline.merge("current_hook_index" => next_index)

    session = Session.create!(
      agent: resolved_agent,
      session_key: SecureRandom.uuid,
      title: "Task Hook: #{phase}/#{pipeline['new_status']} — #{task.title}",
      status: "active",
      transcript: [],
      metadata: {
        type: "task_hook_pipeline",
        task_id: task.id,
        hook_id: hook.id,
        trigger: phase,
        on_status: pipeline["new_status"],
        pipeline: updated_pipeline
      },
      last_activity_at: Time.current
    )

    Tasks::EventLogger.call(
      task: task,
      agent: resolved_agent,
      event_type: "hook_fired",
      summary: "#{phase.capitalize}-hook fired: #{skill ? "skill '#{skill.name}'" : 'default behavior'} on status '#{pipeline['new_status']}'",
      metadata: { hook_id: hook.id, session_id: session.id, skill_name: skill&.name }
    )

    ChatStreamJob.perform_later(session.id, prompt, [])
  end

  def advance_to_next_phase(task, pipeline)
    phase = pipeline["phase"]

    case phase
    when "pre"
      # Pre-hooks done → fire the actual transition
      broadcast_pipeline_status(task, "pre_hook", "completed")
      Tasks::TransitionJob.perform_later(
        pipeline["task_id"],
        pipeline["new_status"],
        pipeline["triggering_agent_id"],
        pipeline["context_json"]
      )
    when "post"
      # Post-hooks done → unlock, pipeline complete
      task.unlock_transition!
      broadcast_pipeline_status(task, "post_hook", "completed")
      broadcast_pipeline_status(task, "pipeline", "completed")
    end
  end

  def broadcast_pipeline_status(task, phase, status)
    ActionCable.server.broadcast("task_#{task.id}", {
      type: "pipeline_status",
      phase: phase,
      status: status,
      task_id: task.id
    })
  end
end
