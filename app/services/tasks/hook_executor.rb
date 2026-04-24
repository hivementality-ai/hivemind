# frozen_string_literal: true

module Tasks
  class HookExecutor
    def self.call(hook:, task:, agent: nil, context: {})
      new(hook: hook, task: task, agent: agent, context: context).call
    end

    def initialize(hook:, task:, agent:, context:)
      @hook = hook
      @task = task
      @context = context

      # Hook agent takes priority — this is the "hand off to next agent" behavior.
      # If the hook specifies an agent, reassign the task and use that agent.
      # Otherwise: task's current assignee wins over the transitioning agent.
      # We reload the task to pick up any reassignments from earlier hooks in the pipeline.
      @agent = resolve_and_reassign_agent(agent)
    end

    def call
      return ServiceResponse.failure(error: "No agent available to execute hook") unless @agent

      skill = @hook.skill
      prompt = build_prompt(skill)

      session = Session.create!(
        agent: @agent,
        session_key: SecureRandom.uuid,
        title: "Task Hook: #{@hook.trigger}/#{@hook.on_status} — #{@task.title}",
        status: "active",
        transcript: [],
        metadata: {
          type: "task_hook",
          task_id: @task.id,
          hook_id: @hook.id,
          trigger: @hook.trigger,
          on_status: @hook.on_status
        },
        last_activity_at: Time.current
      )

      ChatStreamJob.perform_later(session.id, prompt, [])

      skill_label = skill ? "skill '#{skill.name}'" : "default behavior"
      Tasks::EventLogger.call(
        task: @task,
        agent: @agent,
        event_type: "hook_fired",
        summary: "#{@hook.trigger.capitalize}-hook fired: #{skill_label} on status '#{@hook.on_status}'",
        metadata: { hook_id: @hook.id, session_id: session.id, skill_name: skill&.name }
      )

      ServiceResponse.success(data: { session_id: session.id })
    rescue StandardError => e
      ServiceResponse.failure(error: "Hook execution failed: #{e.message}")
    end

    # Public: Build the prompt for a hook execution. Used by pipeline jobs
    # that need to construct prompts without going through the full executor flow.
    def build_prompt(skill = @hook.skill)
      build_hook_prompt(skill)
    end

    private

    # Slim prompt — send the directive, task summary, and instructions.
    # The agent pulls full details (comments, artifacts, checklist, dependencies)
    # via `task_manager` at runtime, saving potentially thousands of tokens.
    def build_hook_prompt(skill)
      parts = []

      # --- Directive header ---
      parts << "## Work Order — Task ##{@task.id}"
      parts << ""
      parts << status_directive
      parts << ""

      # --- Minimal task context (just enough to orient the agent) ---
      parts << "### Task Summary"
      parts << "- **Task ID**: ##{@task.id}"
      parts << "- **Title**: #{@task.title}"
      parts << "- **Status**: #{@task.status}"
      parts << "- **Priority**: #{@task.priority}"
      parts << "- **Assigned to**: #{@task.assigned_to_agent&.name}" if @task.assigned_to_agent
      parts << "- **Due**: #{@task.due_at.strftime('%Y-%m-%d %H:%M')}" if @task.due_at.present?
      parts << "- **Project**: #{@task.project.title}" if @task.project
      parts << "- **Milestone**: #{@task.project_milestone.title}" if @task.project_milestone
      parts << ""

      # Include description — this is the core "what to build" context
      if @task.description.present?
        parts << "### Description"
        parts << @task.description
        parts << ""
      end

      # --- Self-serve instructions ---
      # Instead of dumping full comments, artifacts, checklist, and dependencies
      # into the prompt (which can be thousands of tokens on mature tasks),
      # tell the agent to pull them via task_manager.
      parts << "### Before You Start"
      parts << "Use `task_manager` to read the full task context before beginning work:"
      parts << "```"
      parts << "task_manager action: \"get\", task_id: #{@task.id}"
      parts << "```"
      parts << "This will show you the complete checklist, all comments (including review feedback), artifacts (PRs, branches), and dependencies. **Read it all before writing code.**"
      parts << ""

      # --- Skill or default instructions ---
      if skill
        parts << "### Skill Instructions"
        parts << skill.content
        parts << ""
      else
        parts << "### Instructions"
        parts << default_task_instructions
        parts << ""
      end

      # --- Recording work ---
      parts << "### Recording Your Work"
      parts << "When you produce deliverables, record each one as a task artifact using `task_manager` with `add_artifact`:"
      parts << "- **title**: Short name (e.g. \"feat: auth service (#42)\")"
      parts << "- **type**: `pr`, `branch`, `commit`, `file`, `url`, or `document`"
      parts << "- **url**: Link to the resource"
      parts << "- **description**: One-line summary"
      parts << ""
      parts << "This ensures the next agent in the pipeline knows what you produced and where to find it."
      parts << ""

      if @hook.config.present?
        parts << "### Hook Configuration"
        @hook.config.each { |k, v| parts << "- #{k}: #{v}" }
        parts << ""
      end

      if @context.present?
        parts << "### Additional Context"
        parts << @context.to_s.truncate(5000)
        parts << ""
      end

      parts.join("\n")
    end

    def resolve_and_reassign_agent(fallback_agent)
      # Reload to pick up any reassignment from a prior hook in the pipeline
      @task.reload

      hook_agent = @hook.agent

      if hook_agent
        # Auto-reassign the task to the hook's agent (pipeline handoff)
        if @task.assigned_to_agent != hook_agent
          @task.update!(assigned_to_agent: hook_agent)
          Tasks::EventLogger.call(
            task: @task,
            agent: hook_agent,
            event_type: "auto_assigned",
            summary: "Auto-assigned to #{hook_agent.name} by #{@hook.trigger}-hook on '#{@hook.on_status}'"
          )
        end
        hook_agent
      else
        # Task assignee takes priority over the agent who triggered the transition.
        # This ensures hooks route to whoever owns the ticket NOW, not whoever clicked a button.
        @task.assigned_to_agent || fallback_agent || @task.created_by_agent
      end
    end

    def status_directive
      case @hook.on_status
      when "in_progress"
        "**This is a work order.** Task ##{@task.id} has moved to `in_progress` and is assigned to you. " \
        "Read the task, write the code, open a PR, and move the task to `review` when complete. " \
        "Do NOT acknowledge and close — produce deliverables before this session ends."
      when "review"
        "**This task is ready for review.** Task ##{@task.id} has moved to `review` and is assigned to you. " \
        "Read the task, check the PR, and make a decision: approve and move to `done`, or request changes and move back to `in_progress` with specific feedback. " \
        "Do NOT just acknowledge — complete your review before this session ends."
      when "done"
        "Task ##{@task.id} has been marked `done`. Verify completion, clean up resources, and close out."
      else
        "Task ##{@task.id} has transitioned to `#{@hook.on_status}`. " \
        "Read the task details and take the appropriate action. Produce output — do not just acknowledge."
      end
    end

    def default_task_instructions
      <<~INSTRUCTIONS.strip
        You have been assigned this task. **Produce deliverables before this session ends.**

        For code tasks: use `git worktree` so you're working in an isolated branch — don't work directly on main. Push to the required repo (check the task description/comments for which repo). Create a PR if appropriate and clean up the worktree when done.

        Check off checklist items as you go. When you're done, add a summary comment to the task and move it to `review`. If you get blocked, comment explaining why and stop — don't move to review.

        IMPORTANT: Do NOT respond with just "acknowledged", "queued", or "I'll get to it". You must write code, open PRs, or produce whatever the task requires within this session. If you end this session without deliverables, the task will stall.
      INSTRUCTIONS
    end
  end
end
