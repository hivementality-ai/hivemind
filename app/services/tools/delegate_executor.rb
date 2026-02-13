# frozen_string_literal: true

module Tools
  class DelegateExecutor < BaseExecutor
    # Delegate a task to another agent by name. Creates a session and runs the task through them.
    def call
      agent_name = input["agent"].to_s.strip
      task = input["task"].to_s.strip

      return ServiceResponse.failure(error: "No agent name provided") if agent_name.empty?
      return ServiceResponse.failure(error: "No task provided") if task.empty?

      target = Agent.visible.enabled.where("LOWER(name) = ?", agent_name.downcase).first
      return ServiceResponse.failure(error: "Agent '#{agent_name}' not found. Available: #{available_agents}") unless target

      # Create or find a delegation session
      session = Session.find_or_create_by!(
        agent: target,
        title: "📋 Delegated by #{agent&.name || 'System'}"
      ) do |s|
        s.session_key = "delegate-#{target.id}-#{agent&.id || 'system'}"
        s.status = "active"
        s.metadata = { type: "delegation", delegated_by: agent&.name }
      end

      result = Sessions::Chat.call(
        session: session,
        message: task,
        agent: target
      )

      if result.success?
        reply = result.data[:reply].to_s.truncate(3000)
        ServiceResponse.success(data: {
          output: "#{target.name} responded:\n\n#{reply}",
          exit_code: 0
        })
      else
        ServiceResponse.failure(error: "#{target.name} failed: #{result.error}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Delegation failed: #{e.message}")
    end

    private

    def available_agents
      Agent.visible.enabled.pluck(:name).join(", ")
    end
  end
end
