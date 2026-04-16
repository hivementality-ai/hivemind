# frozen_string_literal: true

module Tasks
  class HookExecutor
    def self.call(hook:, task:, agent: nil, context: {})
      new(hook: hook, task: task, agent: agent, context: context).call
    end

    def initialize(hook:, task:, agent:, context:)
      @hook = hook
      @task = task
      @agent = agent || task.assigned_to_agent || task.created_by_agent
      @context = context
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

    private

    def build_prompt(skill)
      parts = []
      parts << "## Task Hook Execution"
      parts << ""
      parts << "You are executing a #{@hook.trigger}-hook for task status transition to '#{@hook.on_status}'."
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

    def default_task_instructions
      <<~INSTRUCTIONS.strip
        You have been assigned this task. Work through it using your available tools.

        1. Read the task details above carefully — description, checklist, comments, and dependencies.
        2. **If this is a code task** (writing code, fixing bugs, creating PRs, etc.):
           a. Use `git worktree` to create an isolated working directory for your branch. Do NOT work directly in the main checkout.
           b. Create a new branch for your work (e.g., `task-<id>-<short-description>`).
           c. Work inside the worktree directory. This prevents conflicts with other agents working on the same repo.
           d. When done, commit, push, and create a PR. Clean up the worktree when finished (`git worktree remove`).
        3. Do the work described. Follow the checklist items if present.
        4. Check off checklist items as you complete them using `task_manager` with `update_checklist` / `toggle`.
        5. When finished:
           a. Add a summary comment to the task (`task_manager` → `add_comment`) explaining what you did, decisions made, and anything the reviewer should know.
           b. Move the task to `review` (`task_manager` → `move` with status `review`).
        6. If you get blocked or the task is unclear, add a comment explaining why and stop. Do NOT move to review.
      INSTRUCTIONS
    end
  end
end
