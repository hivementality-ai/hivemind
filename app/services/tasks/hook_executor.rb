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
      return ServiceResponse.failure(error: "Hook skill not found") unless @hook.skill

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

      Tasks::EventLogger.call(
        task: @task,
        agent: @agent,
        event_type: "hook_fired",
        summary: "#{@hook.trigger.capitalize}-hook fired: skill '#{skill.name}' on status '#{@hook.on_status}'",
        metadata: { hook_id: @hook.id, session_id: session.id, skill_name: skill.name }
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
      parts << "- Title: #{@task.title}"
      parts << "- Description: #{@task.description}" if @task.description.present?
      parts << "- Status: #{@task.status}"
      parts << "- Priority: #{@task.priority}"
      parts << "- Assigned to: #{@task.assigned_to_agent&.name}" if @task.assigned_to_agent
      parts << ""
      parts << "### Skill Instructions"
      parts << skill.content
      parts << ""

      if @hook.config.present?
        parts << "### Hook Configuration"
        @hook.config.each { |k, v| parts << "- #{k}: #{v}" }
        parts << ""
      end

      if @context.present?
        parts << "### Task Context"
        parts << @context.to_s.truncate(5000)
        parts << ""
      end

      parts.join("\n")
    end
  end
end
