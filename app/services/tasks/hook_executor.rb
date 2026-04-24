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

    def build_hook_prompt(skill)
      parts = []
      parts << "## Work Order — Task ##{@task.id}"
      parts << ""
      parts << status_directive
      parts << ""
      parts << "### Task Details"
      parts << "- **Task ID**: ##{@task.id}"
      parts << "- **Title**: #{@task.title}"
      parts << "- **Status**: #{@task.status}"
      parts << "- **Priority**: #{@task.priority}"
      parts << "- **Assigned to**: #{@task.assigned_to_agent&.name}" if @task.assigned_to_agent
      parts << "- **Created by**: #{@task.created_by_agent&.name}" if @task.created_by_agent
      parts << "- **Due**: #{@task.due_at.strftime('%Y-%m-%d %H:%M')}" if @task.due_at.present?
      parts << "- **Project**: #{@task.project.title}" if @task.project
      parts << "- **Milestone**: #{@task.project_milestone.title}" if @task.project_milestone
      parts << ""

      if @task.description.present?
        parts << "### Description"
        parts << @task.description
        parts << ""
      end

      # Include checklist items
      if @task.checklist.present?
        parts << "### Checklist"
        @task.checklist.each_with_index do |item, idx|
          check = item["checked"] ? "x" : " "
          parts << "- [#{check}] (index #{idx}) #{item['title']}"
        end
        parts << ""
      end

      # Include artifacts as compact references
      if @task.artifacts.present?
        parts << "### Artifacts"
        @task.artifacts.each do |artifact|
          line = "- **#{artifact['title']}** (#{artifact['type']})"
          line += " — #{artifact['url']}" if artifact["url"].present?
          line += " by #{artifact['created_by']}" if artifact["created_by"].present?
          line += ": #{artifact['description']}" if artifact["description"].present?
          parts << line
        end
        parts << ""
      end

      # Include comments (full history)
      if @task.comments.present?
        parts << "### Comments"
        @task.comments.each do |comment|
          parts << "**#{comment['author']}** (#{comment['created_at']}):"
          parts << comment["body"]
          parts << ""
        end
      end

      # Include dependency info
      if @task.task_dependencies.exists?
        parts << "### Dependencies"
        @task.blocking_tasks.each do |dep|
          status_icon = dep.status == "done" ? "✅" : "⏳"
          parts << "- #{status_icon} ##{dep.id}: #{dep.title} (#{dep.status})"
        end
        parts << ""
      end

      # Include tasks that depend on this one
      if @task.inverse_dependencies.exists?
        parts << "### Downstream Tasks (blocked by this task)"
        @task.dependent_tasks.each do |dep|
          parts << "- ##{dep.id}: #{dep.title} (#{dep.status})"
        end
        parts << ""
      end

      if skill
        parts << "### Skill Instructions"
        parts << skill.content
        parts << ""
      else
        parts << "### Instructions"
        parts << default_task_instructions
        parts << ""
      end

      # Always remind agents to record their output as artifacts
      parts << "### Recording Your Work"
      parts << "When you produce deliverables, record each one as a task artifact using the `task_manager` tool with `add_artifact`:"
      parts << "- **title**: Short name (e.g. \"feat: auth service (#42)\", \"feature/auth-module\")"
      parts << "- **type**: `pr`, `branch`, `commit`, `file`, `url`, or `document`"
      parts << "- **url**: Link to the resource (GitHub PR URL, branch URL, doc link, etc.)"
      parts << "- **description**: One-line summary of what it is"
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
        "**This is a work order, not a notification.** You are assigned to task ##{@task.id} " \
        "and you must produce deliverables before this session ends. Read the task details below, " \
        "then do the work — write code, open a PR, run tests, whatever the task requires. " \
        "When finished, move the task to `review`. If blocked, comment with specifics and stop.\n\n" \
        "**Do NOT** simply acknowledge, queue, or defer this task. " \
        "Responding with \"acknowledged\" or \"I'll get to it\" without producing work is not acceptable. " \
        "Complete the work NOW."
      when "review"
        "**This is a review order, not a notification.** Task ##{@task.id} is ready for your review. " \
        "Check the artifacts/PRs attached below, review the code, and make a decision NOW:\n\n" \
        "- **Approve**: Move the task to `done` if the work meets acceptance criteria.\n" \
        "- **Request changes**: Move the task back to `in_progress` with a comment listing specific fixes needed.\n\n" \
        "**Do NOT** simply acknowledge this review request. Produce a review with a clear verdict before this session ends."
      when "done"
        "Task ##{@task.id} has been completed. Verify the deliverables are recorded as artifacts " \
        "and perform any post-completion cleanup (close branches, update docs, notify downstream)."
      else
        "You are handling a task transition to '#{@hook.on_status}' for task ##{@task.id}. " \
        "Read the details below and take the appropriate action. Produce output — do not just acknowledge."
      end
    end

    def default_task_instructions
      <<~INSTRUCTIONS.strip
        You have been assigned this task. **Produce deliverables before this session ends.**

        Read the task details, description, checklist, comments, and dependencies carefully before starting.

        For code tasks: use `git worktree` so you're working in an isolated branch — don't work directly on main. Push to the required repo (check the task description/comments for which repo). Create a PR if appropriate and clean up the worktree when done.

        Check off checklist items as you go. When you're done, add a summary comment to the task and move it to `review`. If you get blocked, comment explaining why and stop — don't move to review.

        IMPORTANT: Do NOT respond with just "acknowledged", "queued", or "I'll get to it". You must write code, open PRs, or produce whatever the task requires within this session. If you end this session without deliverables, the task will stall.
      INSTRUCTIONS
    end
  end
end
