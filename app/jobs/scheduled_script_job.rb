# frozen_string_literal: true

require "open3"
require "timeout"

class ScheduledScriptJob < ApplicationJob
  queue_as :default

  EXEC_TIMEOUT = 120
  MAX_OUTPUT = 50_000
  EXEC_DIR = "/workspace/.hivemind/exec"
  WORKSPACE_CONTAINER = "hivemind-workspace-1"

  INTERPRETERS = {
    ".py" => "python3",
    ".rb" => "ruby",
    ".sh" => "bash",
    ".bash" => "bash"
  }.freeze

  # Runs a scheduled script task
  # @param scheduled_task_id [Integer] The ScheduledTask record ID
  def perform(scheduled_task_id)
    task = ScheduledTask.find_by(id: scheduled_task_id)
    return unless task&.enabled?

    agent = task.agent
    return unless agent

    script_path = task.job_params&.dig("script_path")
    unless script_path.present?
      task.update(last_error_at: Time.current, last_error_message: "No script_path configured")
      return
    end

    # Create a session to log the output
    session = agent.sessions.create!(
      title: "Script: #{task.name}",
      session_type: "scheduled"
    )

    output, exit_code = execute_script(script_path)

    if exit_code == 0
      task.update!(
        last_run_at: Time.current,
        next_run_at: calculate_next_run(task.schedule)
      )

      session.update!(metadata: (session.metadata || {}).merge(
        "output" => output.to_s.truncate(MAX_OUTPUT),
        "exit_code" => exit_code,
        "status" => "success"
      ))
    else
      task.update!(
        last_run_at: Time.current,
        last_error_at: Time.current,
        last_error_message: output.to_s.truncate(500),
        next_run_at: calculate_next_run(task.schedule)
      )

      session.update!(metadata: (session.metadata || {}).merge(
        "output" => output.to_s.truncate(MAX_OUTPUT),
        "exit_code" => exit_code,
        "status" => "error"
      ))
    end
  rescue StandardError => e
    task&.update(last_error_at: Time.current, last_error_message: e.message)
    Rails.logger.error("ScheduledScriptJob failed for task #{scheduled_task_id}: #{e.message}")
  end

  private

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

  def ensure_exec_dir
    Open3.capture3(
      "docker", "exec", WORKSPACE_CONTAINER,
      "bash", "-c", "mkdir -p #{EXEC_DIR}"
    )
  rescue StandardError
    FileUtils.mkdir_p(EXEC_DIR) rescue nil
  end

  def calculate_next_run(cron_expression)
    Fugit::Cron.parse(cron_expression)&.next_time&.to_t
  rescue StandardError
    nil
  end
end
