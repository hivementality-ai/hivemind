# frozen_string_literal: true

module Tools
  class HeartbeatWriteExecutor < BaseExecutor
    # Allows agents to add/remove tasks from the heartbeat checklist.
    #
    # Actions:
    #   add    — Add a temporary (one-off) task. Auto-wiped after the heartbeat processes it.
    #   remove — Remove a temporary task by exact name match. Protected items cannot be removed by agents.
    #   list   — List all tasks, indicating which are protected.
    #   clear  — Wipe all non-protected (temporary) tasks. Protected items survive.
    #
    # Note: Standing (protected) items can only be created by users through the UI.
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
        clear_temporary_tasks
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Supported: add, remove, list, clear")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Heartbeat write failed: #{e.message}")
    end

    private

    def with_tasks_lock(&block)
      setting = Setting.find_or_create_by!(key: "heartbeat_tasks") { |s| s.value = "[]" }
      setting.with_lock do
        tasks = begin
          JSON.parse(setting.reload.value || "[]")
        rescue JSON::ParserError
          []
        end
        result = block.call(tasks)
        setting.update!(value: tasks.to_json)
        result
      end
    end

    def add_task(task)
      with_tasks_lock do |tasks|
        tasks << {
          "task" => task,
          "protected" => false,
          "added_by" => agent&.name,
          "added_at" => Time.current.iso8601
        }
      end

      ServiceResponse.success(data: {
        output: "Added temporary task to heartbeat checklist: #{task}",
        exit_code: 0
      })
    end

    def remove_task(task)
      removed = 0
      blocked = false

      with_tasks_lock do |tasks|
        protected_match = tasks.any? { |t| t["task"] == task && t["protected"] == true }
        before = tasks.size
        tasks.reject! { |t| t["task"] == task && t["protected"] != true }
        removed = before - tasks.size
        blocked = protected_match && removed == 0
      end

      if removed > 0
        ServiceResponse.success(data: {
          output: "Removed #{removed} task(s) matching '#{task}'.",
          exit_code: 0
        })
      elsif blocked
        ServiceResponse.failure(error: "Cannot remove '#{task}' — it is a protected standing item. Only users can delete standing items.")
      else
        ServiceResponse.success(data: { output: "No matching tasks found.", exit_code: 0 })
      end
    end

    def list_tasks
      raw = Setting.get("heartbeat_tasks")
      tasks = begin
        JSON.parse(raw || "[]")
      rescue JSON::ParserError
        []
      end

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
      cleared = 0
      standing_count = 0

      with_tasks_lock do |tasks|
        standing = tasks.select { |t| t["protected"] == true }
        cleared = tasks.size - standing.size
        standing_count = standing.size
        tasks.replace(standing)
      end

      ServiceResponse.success(data: {
        output: "Cleared #{cleared} temporary task(s). #{standing_count} protected standing item(s) preserved.",
        exit_code: 0
      })
    end
  end
end
