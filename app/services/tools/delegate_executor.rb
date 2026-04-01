# frozen_string_literal: true

module Tools
  class DelegateExecutor < BaseExecutor
    # Delegate a task to another agent by name.
    # Runs asynchronously — the delegated agent works in their own session
    # and reports back when done. Use delegation_status to check progress.
    def call
      agent_name = input["agent"].to_s.strip
      task = input["task"].to_s.strip

      return ServiceResponse.failure(error: "No agent name provided") if agent_name.empty?
      return ServiceResponse.failure(error: "No task provided") if task.empty?

      target = Agent.visible.enabled.where("LOWER(name) = ?", agent_name.downcase).first
      return ServiceResponse.failure(error: "Agent '#{agent_name}' not found. Available: #{available_agents}") unless target
      return ServiceResponse.failure(error: "Cannot delegate to yourself — try performing the task directly") if agent&.id == target.id

      task_key = SecureRandom.hex(8)
      parent_session = config[:session]

      sat = SubAgentTask.create!(
        parent_agent: agent || target,
        child_agent: target,
        parent_session: parent_session,
        task: task,
        task_key: task_key,
        status: "pending"
      )

      # Fire and forget — the delegated agent works independently
      SubAgentJob.perform_later(sat.id)

      ServiceResponse.success(data: {
        output: "Delegated to #{target.name}: #{task.truncate(200)}\nTask ID: #{task_key}\n\n#{target.name} is now working on this in their own session. Use delegation_status with this task ID to check progress. They will report back when done.",
        exit_code: 0
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Delegation failed: #{e.message}")
    end

    private

    def available_agents
      Agent.visible.enabled.pluck(:name).join(", ")
    end
  end
end
