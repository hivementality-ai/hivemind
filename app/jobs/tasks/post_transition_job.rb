# frozen_string_literal: true

module Tasks
  class PostTransitionJob < ApplicationJob
    queue_as :system

    # Runs post-hooks after the status change. Resolves agent FRESH from task state.
    # Unlocks the task after all post-hooks complete (or immediately if none).
    def perform(task_id, new_status, triggering_agent_id, context_json)
      task = Task.find(task_id)
      agent = triggering_agent_id ? Agent.find_by(id: triggering_agent_id) : nil
      context = JSON.parse(context_json)

      broadcast_pipeline_status(task, "post_hook", "running")

      # Trigger post-task reflection when a task reaches done.
      # Enqueued on :low so it never contends with the hook pipeline.
      maybe_trigger_reflection(task, new_status, agent)

      # Emit outbound webhook for task completion.
      if new_status == "done"
        WebhookEmitter.emit(
          "task.completed",
          { task_id: task.id, title: task.title, status: new_status, agent_id: agent&.id },
          agent: agent, team: agent&.team
        )
      end

      # Find post-hooks for the new status
      hooks = task.effective_hooks_for(new_status, "post")

      if hooks.empty?
        # No post-hooks — unlock and we're done
        task.unlock_transition!
        broadcast_pipeline_status(task, "post_hook", "completed")
        return
      end

      # Run post-hooks. Same chaining pattern as pre-hooks.
      pipeline_meta = {
        task_id: task_id,
        new_status: new_status,
        triggering_agent_id: triggering_agent_id,
        context_json: context_json,
        phase: "post",
        hook_ids: hooks.map(&:id),
        current_hook_index: 0
      }

      execute_next_hook(task, hooks.first, agent, context, pipeline_meta)
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn("[PostTransitionJob] Record not found: #{e.message}")
    rescue => e
      task&.unlock_transition! if task&.transition_locked?
      broadcast_pipeline_status(task, "post_hook", "failed", error: e.message) if task
      Rails.logger.error("[PostTransitionJob] Error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    end

    private

    def execute_next_hook(task, hook, fallback_agent, context, pipeline_meta)
      # Reload task to pick up any reassignment from a prior hook
      task.reload

      # Resolve agent fresh — whoever's on the ticket NOW
      resolved_agent = resolve_agent(hook, task, fallback_agent)

      unless resolved_agent
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
          summary: "Auto-assigned to #{hook.agent.name} by post-hook on '#{pipeline_meta[:new_status]}'"
        )
      end

      skill = hook.skill
      prompt = Tasks::HookExecutor.new(
        hook: hook, task: task, agent: resolved_agent, context: context
      ).build_prompt(skill)

      session = Session.create!(
        agent: resolved_agent,
        session_key: SecureRandom.uuid,
        title: "Task Hook: post/#{pipeline_meta[:new_status]} — #{task.title}",
        status: "active",
        transcript: [],
        metadata: {
          type: "task_hook_pipeline",
          task_id: task.id,
          hook_id: hook.id,
          trigger: "post",
          on_status: pipeline_meta[:new_status],
          pipeline: pipeline_meta
        },
        last_activity_at: Time.current
      )

      Tasks::EventLogger.call(
        task: task,
        agent: resolved_agent,
        event_type: "hook_fired",
        summary: "Post-hook fired: #{skill ? "skill '#{skill.name}'" : 'default behavior'} on status '#{pipeline_meta[:new_status]}'",
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
        # More post-hooks to run
        next_hook = TaskHook.find(hook_ids[next_index])
        pipeline_meta[:current_hook_index] = next_index
        execute_next_hook(task, next_hook, nil, JSON.parse(pipeline_meta[:context_json]), pipeline_meta)
      else
        # All post-hooks done — unlock the task, pipeline complete
        task.unlock_transition!
        broadcast_pipeline_status(task, "post_hook", "completed")
        broadcast_pipeline_status(task, "pipeline", "completed")
      end
    end

    # Enqueues PostTaskReflectionJob when the task moves to done and an agent is available.
    # Fires regardless of whether hooks are present so reflection is not skipped
    # if the task has no configured hooks.
    def maybe_trigger_reflection(task, new_status, agent)
      return unless new_status == "done"

      resolved_agent = agent || task.assigned_to_agent || task.created_by_agent
      return unless resolved_agent

      PostTaskReflectionJob.perform_later(resolved_agent.id, task_id: task.id)
    rescue StandardError => e
      Rails.logger.warn("[PostTransitionJob] Failed to enqueue reflection: #{e.message}")
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
