# frozen_string_literal: true

module Tools
  class CodingAgentStatusExecutor < BaseExecutor
    def call
      action = input["action"].to_s.strip.presence || "status"
      task_key = input["task_key"].to_s.strip

      case action
      when "status"
        return ServiceResponse.failure(error: "No task_key provided") if task_key.empty?
        check_status(task_key)
      when "list"
        list_tasks
      when "kill"
        return ServiceResponse.failure(error: "No task_key provided") if task_key.empty?
        kill_task(task_key)
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Supported: status, list, kill")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Coding agent status failed: #{e.message}")
    end

    private

    def check_status(task_key)
      task = CodingAgentTask.find_by(task_key: task_key)
      return ServiceResponse.failure(error: "Task not found: #{task_key}") unless task

      # Check if task belongs to current agent
      unless task.agent == agent || agent.nil?
        return ServiceResponse.failure(error: "Task #{task_key} not found or not accessible")
      end

      output = []
      output << "🤖 Coding Agent Task: #{task_key}"
      output << "Task: #{task.task.truncate(100)}"
      output << "CLI: #{task.cli}"
      output << "Model: #{task.model}" if task.model.present?
      output << "Status: #{format_status(task.status)}"
      output << "Timeout: #{task.timeout}s"
      output << "Duration: #{task.duration_seconds}s" if task.started_at

      if task.process_info.present?
        output << "Process ID: #{task.process_info['pid']}"
      end

      if task.completed? || task.failed?
        output << ""
        output << "=== Output ==="
        if task.output.present?
          output << task.output.last(4000) # Show last 4000 chars
        else
          output << "(No output captured)"
        end
      elsif task.running?
        output << ""
        output << "=== Recent Output ==="
        if task.output.present?
          output << task.output.last(2000) # Show last 2000 chars for running tasks
        else
          output << "(Still starting...)"
        end
        output << ""
        output << "💡 The coding agent is still running. Check again in a few moments for updates."
      end

      ServiceResponse.success(data: { output: output.join("\n"), exit_code: 0 })
    end

    def list_tasks
      # Show tasks for current agent, or all if no agent context
      tasks = if agent
                CodingAgentTask.for_agent(agent).recent
      else
                CodingAgentTask.recent
      end

      if tasks.any?
        output = [ "🤖 Coding Agent Tasks:\n" ]
        tasks.each do |task|
          icon = format_status_icon(task.status)
          duration_text = task.duration_seconds ? "(#{task.duration_seconds}s)" : ""
          output << "#{icon} [#{task.task_key}] #{task.cli}: #{task.task.truncate(60)} #{duration_text}"
        end
        ServiceResponse.success(data: { output: output.join("\n"), exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "No coding agent tasks found.", exit_code: 0 })
      end
    end

    def kill_task(task_key)
      task = CodingAgentTask.find_by(task_key: task_key)
      return ServiceResponse.failure(error: "Task not found: #{task_key}") unless task

      # Check if task belongs to current agent
      unless task.agent == agent || agent.nil?
        return ServiceResponse.failure(error: "Task #{task_key} not found or not accessible")
      end

      unless task.active?
        return ServiceResponse.failure(error: "Task #{task_key} is not active (status: #{task.status})")
      end

      if task.process_info&.dig("pid")
        begin
          pid = task.process_info["pid"]
          # Try to kill the process group
          Process.kill("TERM", -pid) # Negative PID kills process group
          sleep 2.seconds
          Process.kill("KILL", -pid) rescue nil
        rescue Errno::ESRCH
          # Process already dead
        rescue StandardError => e
          Rails.logger.warn("[CodingAgent] Failed to kill process #{pid}: #{e.message}")
        end
      end

      task.update!(
        status: "failed",
        output: "#{task.output}\n\n=== Task manually killed ===",
        completed_at: Time.current
      )

      ServiceResponse.success(data: {
        output: "💀 Killed coding agent task #{task_key}",
        exit_code: 0
      })
    end

    def format_status(status)
      case status
      when "pending" then "⏳ Pending"
      when "running" then "🔄 Running"
      when "completed" then "✅ Completed"
      when "failed" then "❌ Failed"
      else status
      end
    end

    def format_status_icon(status)
      case status
      when "pending" then "⏳"
      when "running" then "🔄"
      when "completed" then "✅"
      when "failed" then "❌"
      else "❓"
      end
    end
  end
end
