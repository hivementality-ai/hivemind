# frozen_string_literal: true

module Tools
  class SpawnExecutor < BaseExecutor
    # Spawn a sub-agent to handle a task asynchronously.
    # Returns immediately with a task_key. Parent keeps working.
    def call
      agent_name = input["agent"].to_s.strip
      task = input["task"].to_s.strip

      return ServiceResponse.failure(error: "No agent name provided") if agent_name.empty?
      return ServiceResponse.failure(error: "No task provided") if task.empty?

      target = Agent.visible.enabled.where("LOWER(name) = ?", agent_name.downcase).first
      return ServiceResponse.failure(error: "Agent '#{agent_name}' not found. Available: #{available_agents}") unless target

      task_key = SecureRandom.hex(8)

      # Find parent session from context
      parent_session = find_parent_session

      sat = SubAgentTask.create!(
        parent_agent: agent || target, # fallback if no parent agent context
        child_agent: target,
        parent_session: parent_session,
        task: task,
        task_key: task_key,
        status: "pending"
      )

      # Fire and forget — runs in background
      SubAgentJob.perform_later(sat.id)

      ServiceResponse.success(data: {
        output: "Spawned #{target.name} for: #{task.truncate(100)}\nTask ID: #{task_key}\nUse spawn_status tool with this ID to check progress.",
        exit_code: 0
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Spawn failed: #{e.message}")
    end

    private

    def available_agents
      Agent.visible.enabled.pluck(:name).join(", ")
    end

    def find_parent_session
      return nil unless agent
      Session.where(agent: agent).order(updated_at: :desc).first
    end
  end
end
