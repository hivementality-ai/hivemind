# frozen_string_literal: true

module Tools
  class CronExecutor < BaseExecutor
    # Manage scheduled tasks — create, list, delete, run
    def call
      action = input["action"].to_s.strip

      case action
      when "list"
        list_tasks
      when "create", "add"
        create_task
      when "delete", "remove"
        delete_task
      when "run"
        run_task
      else
        ServiceResponse.failure(error: "Unknown cron action: #{action}. Supported: list, create, delete, run")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Cron error: #{e.message}")
    end

    private

    def list_tasks
      tasks = ScheduledTask.order(created_at: :desc).limit(20)

      if tasks.any?
        output = tasks.map do |t|
          status = t.enabled? ? "✅" : "⏸️"
          "#{status} [#{t.id}] #{t.name} — #{t.schedule} (#{t.task_type})"
        end.join("\n")
        ServiceResponse.success(data: { output: "Scheduled tasks:\n#{output}", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "No scheduled tasks.", exit_code: 0 })
      end
    end

    def create_task
      name = input["name"].to_s.strip
      schedule = input["schedule"].to_s.strip
      command = input["command"].to_s.strip
      task_type = input["task_type"].to_s.strip.presence || "shell"

      return ServiceResponse.failure(error: "Name required") if name.empty?
      return ServiceResponse.failure(error: "Schedule required (cron expression or 'every 5m')") if schedule.empty?
      return ServiceResponse.failure(error: "Command required") if command.empty?

      task = ScheduledTask.create!(
        name: name,
        schedule: schedule,
        command: command,
        task_type: task_type,
        agent: agent,
        enabled: true
      )

      ServiceResponse.success(data: {
        output: "Created scheduled task: #{task.name} (#{task.id})\nSchedule: #{task.schedule}\nCommand: #{task.command}",
        exit_code: 0
      })
    end

    def delete_task
      task_id = input["task_id"].to_s.strip
      return ServiceResponse.failure(error: "task_id required") if task_id.empty?

      task = ScheduledTask.find(task_id)
      task.destroy!

      ServiceResponse.success(data: { output: "Deleted task: #{task.name}", exit_code: 0 })
    end

    def run_task
      task_id = input["task_id"].to_s.strip
      return ServiceResponse.failure(error: "task_id required") if task_id.empty?

      task = ScheduledTask.find(task_id)

      # Execute the command immediately
      case task.task_type
      when "shell"
        stdout, stderr, status = Open3.capture3(task.command, timeout: 60)
        output = stdout.presence || stderr
        ServiceResponse.success(data: {
          output: "Ran task #{task.name}:\n#{output.to_s.truncate(5000)}",
          exit_code: status.exitstatus
        })
      else
        ServiceResponse.failure(error: "Unsupported task_type: #{task.task_type}")
      end
    end
  end
end
