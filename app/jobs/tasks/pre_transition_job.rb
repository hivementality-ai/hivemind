# frozen_string_literal: true

module Tasks
  class PreTransitionJob < ApplicationJob
    queue_as :default

    # Fires pre-hooks for a task transition. Locks the task to prevent races.
    # If pre-hooks create sessions (async agent work), the pipeline continues
    # via ChatStreamJob's pipeline continuation callback.
    # If no pre-hooks exist, immediately fires TransitionJob.
    def perform(task_id, new_status, triggering_agent_id, context_json)
      task = Task.find(task_id)
      agent = triggering_agent_id ? Agent.find_by(id: triggering_agent_id) : nil
      context = JSON.parse(context_json)

      # Lock the task to prevent concurrent transitions
      task.lock_transition!(agent)

      # Broadcast lock state to UI
      broadcast_pipeline_status(task, "pre_hook", "running")

      # Find pre-hooks for the target status
      hooks = task.effective_hooks_for(new_status, "pre")

      if hooks.empty?
        # No pre-hooks — skip straight to transition
        Tasks::TransitionJob.perform_later(task_id, new_status, triggering_agent_id, context_json)
        return
      end

      # Run each pre-hook. The last hook's session carries the pipeline forward.
      # For multiple pre-hooks, we chain them: each hook's session completion
      # triggers the next hook, and the final one triggers TransitionJob.
      pipeline_meta = {
        task_id: task_id,
        new_status: new_status,
        triggering_agent_id: triggering_agent_id,
        context_json: context_json,
        phase: "pre",
        hook_ids: hooks.map(&:id),
        current_hook_index: 0
      }

      execute_next_hook(task, hooks.first, agent, context, pipeline_meta)
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn("[PreTransitionJob] Record not found: #{e.message}")
    rescue => e
      # On failure, unlock the task so it's not stuck
      task&.unlock_transition! if task&.transition_locked?
      broadcast_pipeline_status(task, "pre_hook", "failed", error: e.message) if task
      Rails.logger.error("[PreTransitionJob] Error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    end

    private

    def execute_next_hook(task, hook, fallback_agent, context, pipeline_meta)
      # Reload task to pick up any reassignment from a prior hook
      task.reload

      # Resolve agent: task assignee takes priority
      resolved_agent = resolve_agent(hook, task, fallback_agent)

      unless resolved_agent
        # No agent available — skip this hook, try next or continue pipeline
        advance_pipeline(task, pipeline_meta)
        return
      end

      # If hook has an explicit agent, reassign the task
      if hook.agent && task.assigned_to_agent != hook.agent
        task.update!(assigned_to_agent: hook.agent)
        Tasks::EventLogger.call(
          task: task,
          agent: hook.agent,
          event_type: "auto_assigned",
          summary: "Auto-assigned to #{hook.agent.name} by pre-hook on '#{pipeline_meta[:new_status]}'"
        )
      end

      skill = hook.skill
      prompt = Tasks::HookExecutor.new(
        hook: hook, task: task, agent: resolved_agent, context: context
      ).build_prompt(skill)

      session = Session.create!(
        agent: resolved_agent,
        session_key: SecureRandom.uuid,
        title: "Task Hook: pre/#{pipeline_meta[:new_status]} — #{task.title}",
        status: "active",
        transcript: [],
        metadata: {
          type: "task_hook_pipeline",
          task_id: task.id,
          hook_id: hook.id,
          trigger: "pre",
          on_status: pipeline_meta[:new_status],
          pipeline: pipeline_meta
        },
        last_activity_at: Time.current
      )

      Tasks::EventLogger.call(
        task: task,
        agent: resolved_agent,
        event_type: "hook_fired",
        summary: "Pre-hook fired: #{skill ? "skill '#{skill.name}'" : 'default behavior'} on status '#{pipeline_meta[:new_status]}'",
        metadata: { hook_id: hook.id, session_id: session.id, skill_name: skill&.name }
      )

      ChatStreamJob.perform_later(session.id, prompt, [])
    end

    def resolve_agent(hook, task, fallback_agent)
      hook.agent || task.assigned_to_agent || fallback_agent || task.created_by_agent
    end

    def advance_pipeline(task, pipeline_meta)
      next_index = pipeline_meta[:current_hook_index] + 1
      hook_ids = pipeline_meta[:hook_ids]

      if next_index < hook_ids.length
        # More pre-hooks to run
        next_hook = TaskHook.find(hook_ids[next_index])
        pipeline_meta[:current_hook_index] = next_index
        execute_next_hook(task, next_hook, nil, JSON.parse(pipeline_meta[:context_json]), pipeline_meta)
      else
        # All pre-hooks done — fire the transition
        Tasks::TransitionJob.perform_later(
          pipeline_meta[:task_id],
          pipeline_meta[:new_status],
          pipeline_meta[:triggering_agent_id],
          pipeline_meta[:context_json]
        )
      end
    end

    def broadcast_pipeline_status(task, phase, status, error: nil)
      return unless task

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
