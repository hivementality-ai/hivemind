# frozen_string_literal: true

module Tools
  class HeartbeatWriteExecutor < BaseExecutor
    # Allows agents to add/remove tasks from the heartbeat checklist.
    #
    # Actions:
    #   add           — Add a temporary (one-off) task. Auto-wiped after the heartbeat processes it.
    #   add_standing  — Add a protected (permanent) standing item. Only users can delete these.
    #   remove        — Remove a task by name match. Protected items cannot be removed by agents.
    #   list          — List all tasks, indicating which are protected.
    #   clear         — Wipe all non-protected (temporary) tasks. Protected items survive.
    def call
      action = input["action"].to_s.strip.presence || "add"
      task = input["task"].to_s.strip

      case action
      when "add"
        return ServiceResponse.failure(error: "No task provided") if task.empty?
        add_task(task, protected: false)
      when "add_standing"
        return ServiceResponse.failure(error: "No task provided") if task.empty?
        add_task(task, protected: true)
      when "remove"
        return ServiceResponse.failure(error: "No task provided") if task.empty?
        remove_task(task)
      when "list"
        list_tasks
      when "clear"
        clear_temporary_tasks
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Supported: add, add_standing, remove, list, clear")
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

    def add_task(task, protected:)
      tasks = current_tasks
      tasks << {
        "task" => task,
        "protected" => protected,
        "added_by" => agent&.name,
        "added_at" => Time.current.iso8601
      }
      save_tasks(tasks)

      label = protected ? "standing (protected)" : "temporary"
      ServiceResponse.success(data: {
        output: "Added #{label} task to heartbeat checklist: #{task}\n#{tasks.size} total tasks.",
        exit_code: 0
      })
    end

    def remove_task(task)
      tasks = current_tasks
      before = tasks.size

      protected_matches = tasks.select { |t| t["task"].downcase.include?(task.downcase) && t["protected"] == true }
      tasks.reject! { |t| t["task"].downcase.include?(task.downcase) && t["protected"] != true }
      save_tasks(tasks)

      removed = before - tasks.size

      if removed > 0
        ServiceResponse.success(data: {
          output: "Removed #{removed} task(s) matching '#{task}'.",
          exit_code: 0
        })
      elsif protected_matches.any?
        ServiceResponse.failure(error: "Cannot remove '#{task}' — it is a protected standing item. Only users can delete standing items.")
      else
        ServiceResponse.success(data: { output: "No matching tasks found.", exit_code: 0 })
      end
    end

    def list_tasks
      tasks = current_tasks

      if tasks.any?
        output = tasks.map.with_index do |t, i|
          lock = t["protected"] ? " 🔒" : ""
          "#{i + 1}.#{lock} #{t["task"]} (added by #{t["added_by"] || "unknown"})"
        end.join("\n")
        ServiceResponse.success(data: { output: "Heartbeat checklist:\n#{output}", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "Heartbeat checklist is empty.", exit_code: 0 })
      end
    end

    def clear_temporary_tasks
      tasks = current_tasks
      standing = tasks.select { |t| t["protected"] == true }
      cleared = tasks.size - standing.size
      save_tasks(standing)

      ServiceResponse.success(data: {
        output: "Cleared #{cleared} temporary task(s). #{standing.size} protected standing item(s) preserved.",
        exit_code: 0
      })
    end
  end
end
