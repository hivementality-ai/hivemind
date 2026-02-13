# frozen_string_literal: true

module Tools
  class HeartbeatWriteExecutor < BaseExecutor
    # Allows agents to add/remove tasks from the heartbeat checklist
    def call
      action = input["action"].to_s.strip.presence || "add"
      task = input["task"].to_s.strip

      case action
      when "add"
        return ServiceResponse.failure(error: "No task provided") if task.empty?
        add_task(task)
      when "remove"
        return ServiceResponse.failure(error: "No task provided") if task.empty?
        remove_task(task)
      when "list"
        list_tasks
      when "clear"
        clear_tasks
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Supported: add, remove, list, clear")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Heartbeat write failed: #{e.message}")
    end

    private

    def current_tasks
      raw = Setting.get("heartbeat_tasks")
      return [] unless raw

      JSON.parse(raw)
    rescue JSON::ParserError
      []
    end

    def save_tasks(tasks)
      Setting.set("heartbeat_tasks", tasks.to_json)
    end

    def add_task(task)
      tasks = current_tasks
      tasks << { "task" => task, "added_by" => agent&.name, "added_at" => Time.current.iso8601 }
      save_tasks(tasks)

      ServiceResponse.success(data: {
        output: "Added to heartbeat checklist: #{task}\n#{tasks.size} total tasks.",
        exit_code: 0
      })
    end

    def remove_task(task)
      tasks = current_tasks
      before = tasks.size
      tasks.reject! { |t| t["task"].downcase.include?(task.downcase) }
      save_tasks(tasks)

      removed = before - tasks.size
      ServiceResponse.success(data: {
        output: removed > 0 ? "Removed #{removed} task(s) matching '#{task}'." : "No matching tasks found.",
        exit_code: 0
      })
    end

    def list_tasks
      tasks = current_tasks

      if tasks.any?
        output = tasks.map.with_index do |t, i|
          "#{i + 1}. #{t["task"]} (added by #{t["added_by"] || "unknown"})"
        end.join("\n")
        ServiceResponse.success(data: { output: "Heartbeat checklist:\n#{output}", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "Heartbeat checklist is empty.", exit_code: 0 })
      end
    end

    def clear_tasks
      save_tasks([])
      ServiceResponse.success(data: { output: "Heartbeat checklist cleared.", exit_code: 0 })
    end
  end
end
