# frozen_string_literal: true

module Tools
  class DelegationStatusExecutor < BaseExecutor
    # Check status of a delegated task, or list recent delegations.
    def call
      task_key = input["task_key"].to_s.strip
      action = input["action"].to_s.strip.presence || "status"

      case action
      when "status"
        return ServiceResponse.failure(error: "No task_key provided") if task_key.empty?
        check_status(task_key)
      when "list"
        list_tasks
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Supported: status, list")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Delegation status failed: #{e.message}")
    end

    private

    def check_status(task_key)
      sat = SubAgentTask.find_by(task_key: task_key)
      return ServiceResponse.failure(error: "Task not found: #{task_key}") unless sat

      output = []
      output << "Task: #{sat.task.truncate(100)}"
      output << "Agent: #{sat.child_agent.name}"
      output << "Status: #{sat.status}"
      output << "Duration: #{sat.duration_seconds}s" if sat.started_at

      if sat.status == "completed" || sat.status == "failed"
        output << ""
        output << "Result:"
        output << sat.result.to_s.truncate(3000)
      end

      ServiceResponse.success(data: { output: output.join("\n"), exit_code: 0 })
    end

    def list_tasks
      tasks = agent ? SubAgentTask.where(parent_agent: agent).recent : SubAgentTask.recent

      if tasks.any?
        output = tasks.map do |sat|
          icon = case sat.status
          when "completed" then "✅"
          when "failed" then "❌"
          when "running" then "🔄"
          else "⏳"
          end
          "#{icon} [#{sat.task_key}] #{sat.child_agent.name}: #{sat.task.truncate(60)} (#{sat.status})"
        end.join("\n")
        ServiceResponse.success(data: { output: "Delegated tasks:\n#{output}", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "No delegated tasks found.", exit_code: 0 })
      end
    end
  end
end
