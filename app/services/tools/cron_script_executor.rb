# frozen_string_literal: true

require "open3"
require "timeout"

module Tools
  class CronScriptExecutor < BaseExecutor
    EXEC_TIMEOUT = 120
    MAX_OUTPUT = 50_000
    WORKSPACE_ROOT = "/workspace"
    EXEC_DIR = "/workspace/.hivemind/exec"
    WORKSPACE_CONTAINER = "hivemind-workspace-1"

    INTERPRETERS = {
      ".py" => "python3",
      ".rb" => "ruby",
      ".sh" => "bash",
      ".bash" => "bash"
    }.freeze

    def call
      action = input["action"].to_s.strip

      case action
      when "list"
        list_tasks
      when "create", "add"
        create_task
      when "confirm_create"
        confirm_create_task
      when "delete", "remove"
        delete_task
      when "run"
        run_task
      when "update_script"
        update_script
      else
        ServiceResponse.failure(error: "Unknown cron_script action: #{action}. Supported: list, create, confirm_create, delete, run, update_script")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Cron script error: #{e.message}")
    end

    private

    def list_tasks
      tasks = ScheduledTask.where(agent_id: agent.id, job_class: "ScheduledScriptJob").order(created_at: :desc).limit(20)

      if tasks.any?
        output = tasks.map do |t|
          status = t.enabled? ? "✅" : "⏸️"
          frequency = CronParser.parse(t.schedule)
          script = t.job_params&.dig("script_path") || "no script"
          "#{status} [#{t.id}] #{t.name} — #{frequency} — #{script}"
        end.join("\n")
        ServiceResponse.success(data: { output: "Scheduled scripts:\n#{output}", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "No scheduled scripts.", exit_code: 0 })
      end
    end

    def create_task
      name = input["name"].to_s.strip
      schedule = input["schedule"].to_s.strip
      script_path = input["script_path"].to_s.strip
      confirm = input["confirm"].to_s.downcase != "false"

      return ServiceResponse.failure(error: "name required") if name.empty?
      return ServiceResponse.failure(error: "schedule required (cron expression)") if schedule.empty?
      return ServiceResponse.failure(error: "script_path required") if script_path.empty?
      return ServiceResponse.failure(error: "script_path must be under /workspace/") unless script_path.start_with?("/workspace/")

      # Validate script exists in workspace
      return ServiceResponse.failure(error: "Script not found: #{script_path}") unless script_exists?(script_path)

      job_params = { "script_path" => script_path }
      description_hint = "Run script: #{script_path}"

      if confirm
        result = Agents::CronConfirmation.generate_explanation(
          agent: agent,
          name: name,
          schedule: schedule,
          job_class: "ScheduledScriptJob",
          job_params: job_params,
          description_hint: description_hint
        )

        ServiceResponse.success(data: result)
      else
        task = ScheduledTask.create!(
          agent: agent,
          name: name,
          schedule: schedule,
          job_class: "ScheduledScriptJob",
          job_params: job_params,
          description: description_hint,
          confirmation_status: "active",
          enabled: true
        )

        ServiceResponse.success(data: {
          status: "created",
          task_id: task.id,
          message: "#{task.name} scheduled ✅ — #{script_path}",
          next_run: task.next_run_at&.strftime("%Y-%m-%d %H:%M:%S %Z") || "Pending"
        })
      end
    end

    def confirm_create_task
      confirmation_id = input["confirmation_id"].to_s.strip
      return ServiceResponse.failure(error: "confirmation_id required") if confirmation_id.empty?

      result = Agents::CronConfirmation.confirm_and_persist(
        confirmation_id: confirmation_id,
        agent: agent
      )

      if result[:status] == "error"
        ServiceResponse.failure(error: result[:message])
      else
        ServiceResponse.success(data: result)
      end
    end

    def delete_task
      task_id = input["task_id"].to_s.strip
      return ServiceResponse.failure(error: "task_id required") if task_id.empty?

      task = ScheduledTask.find(task_id)
      return ServiceResponse.failure(error: "You do not own this task") unless task.agent_id == agent.id

      task.destroy!
      ServiceResponse.success(data: { output: "Deleted script task: #{task.name}", exit_code: 0 })
    end

    def run_task
      task_id = input["task_id"].to_s.strip
      return ServiceResponse.failure(error: "task_id required") if task_id.empty?

      task = ScheduledTask.find(task_id)
      return ServiceResponse.failure(error: "You do not own this task") unless task.agent_id == agent.id

      script_path = task.job_params&.dig("script_path")
      return ServiceResponse.failure(error: "No script_path configured for this task") if script_path.blank?

      output, exit_code = execute_script(script_path)

      task.update!(last_run_at: Time.current)

      if exit_code == 0
        ServiceResponse.success(data: { output: "Executed #{task.name} ✅\n#{output}".truncate(MAX_OUTPUT), exit_code: exit_code })
      else
        task.update!(last_error_at: Time.current, last_error_message: output.to_s.truncate(500))
        ServiceResponse.failure(
          error: "Script exited with code #{exit_code}",
          data: { output: output.to_s.truncate(MAX_OUTPUT), exit_code: exit_code }
        )
      end
    end

    def update_script
      task_id = input["task_id"].to_s.strip
      script_path = input["script_path"].to_s.strip

      return ServiceResponse.failure(error: "task_id required") if task_id.empty?
      return ServiceResponse.failure(error: "script_path required") if script_path.empty?
      return ServiceResponse.failure(error: "script_path must be under /workspace/") unless script_path.start_with?("/workspace/")

      task = ScheduledTask.find(task_id)
      return ServiceResponse.failure(error: "You do not own this task") unless task.agent_id == agent.id

      return ServiceResponse.failure(error: "Script not found: #{script_path}") unless script_exists?(script_path)

      job_params = (task.job_params || {}).merge("script_path" => script_path)
      task.update!(job_params: job_params, description: "Run script: #{script_path}")

      ServiceResponse.success(data: {
        output: "Updated script path for #{task.name} → #{script_path} ✅",
        exit_code: 0
      })
    end

    def execute_script(script_path)
      ext = File.extname(script_path).downcase
      interpreter = INTERPRETERS[ext] || "bash"
      command = "#{interpreter} #{script_path}"

      ensure_exec_dir

      job_id = SecureRandom.hex(8)
      exec_script_path = File.join(EXEC_DIR, "#{job_id}.sh")

      script_content = <<~BASH
        #!/bin/bash
        cd /workspace
        #{command}
      BASH

      IO.popen(
        [ "docker", "exec", "-i", WORKSPACE_CONTAINER, "bash", "-c", "cat > #{exec_script_path} && chmod 755 #{exec_script_path}" ],
        "w"
      ) { |io| io.write(script_content) }

      stdout, _stderr, status = nil

      Timeout.timeout(EXEC_TIMEOUT) do
        stdout, _stderr, status = Open3.capture3(
          "docker", "exec", WORKSPACE_CONTAINER,
          "bash", "-c",
          "#{exec_script_path} 2>&1; echo \"__HIVEMIND_EXIT__$?\""
        )
      end

      lines = stdout.to_s.lines
      exit_code = if lines.last&.start_with?("__HIVEMIND_EXIT__")
                    code = lines.last.sub("__HIVEMIND_EXIT__", "").strip.to_i
                    stdout = lines[0..-2].join
                    code
      else
                    status&.exitstatus || 1
      end

      # Cleanup
      Open3.capture3(
        "docker", "exec", WORKSPACE_CONTAINER,
        "bash", "-c", "rm -f #{exec_script_path}"
      ) rescue nil

      [ stdout.to_s, exit_code ]
    rescue Timeout::Error
      [ "Script timed out after #{EXEC_TIMEOUT}s", 1 ]
    end

    def script_exists?(script_path)
      _, _, status = Open3.capture3(
        "docker", "exec", WORKSPACE_CONTAINER,
        "test", "-f", script_path
      )
      status.success?
    rescue StandardError
      # Fallback: check directly
      File.exist?(script_path)
    end

    def ensure_exec_dir
      Open3.capture3(
        "docker", "exec", WORKSPACE_CONTAINER,
        "bash", "-c", "mkdir -p #{EXEC_DIR}"
      )
    rescue StandardError
      FileUtils.mkdir_p(EXEC_DIR) rescue nil
    end
  end
end
