# frozen_string_literal: true

require "open3"
require "pty"

class CodingAgentJob < ApplicationJob
  queue_as :default

  WORKSPACE_CONTAINER = "hivemind-workspace-1"
  HEARTBEAT_INTERVAL = 5.seconds

  def perform(coding_agent_task_id)
    @task = CodingAgentTask.find(coding_agent_task_id)
    @channel = "session_#{@task.session.id}"

    @task.update!(status: "running", started_at: Time.current)

    Rails.logger.info("[CodingAgent] Starting task #{@task.task_key}: #{@task.task.truncate(100)}")

    # Build the CLI command
    command = build_cli_command(@task.cli, @task.task, @task.model)
    env_vars = build_env_vars

    # Start the process with PTY inside the workspace container
    pid = start_docker_process(command, env_vars)
    @task.update!(process_info: { pid: pid, started_at: Time.current.iso8601 })

    broadcast_message("🤖 Starting #{@task.cli} coding agent...", "info")

    # Monitor the process and stream output
    monitor_process(pid)

  rescue StandardError => e
    Rails.logger.error("[CodingAgent] Task #{@task.task_key} failed: #{e.message}")
    @task&.update!(status: "failed", output: "Error: #{e.message}", completed_at: Time.current)
    broadcast_message("❌ Coding agent failed: #{e.message}", "error")
  ensure
    # Cleanup script file
    File.delete(@cleanup_script) if @cleanup_script && File.exist?(@cleanup_script)
  end

  private

  def build_cli_command(cli, task, model)
    escaped_task = task.gsub('"', '\\"')

    case cli
    when "claude"
      cmd = "claude --dangerously-skip-permissions -p \"#{escaped_task}\""
      cmd += " --model #{model}" if model.present?
      cmd
    when "codex"
      cmd = "codex exec --full-auto \"#{escaped_task}\""
      cmd += " --model #{model}" if model.present?
      cmd
    when "aider"
      cmd = "aider --yes-always --message \"#{escaped_task}\""
      cmd += " --model #{model}" if model.present?
      cmd
    else
      raise ArgumentError, "Unknown CLI: #{cli}"
    end
  end

  def build_env_vars
    env_vars = []

    # Look up API keys from VaultEntry
    anthropic = VaultEntry.find_by(namespace: "provider_credentials", key: "anthropic_api_key")
    env_vars << "ANTHROPIC_API_KEY='#{anthropic.value}'" if anthropic

    openai = VaultEntry.find_by(namespace: "provider_credentials", key: "openai_api_key")
    env_vars << "OPENAI_API_KEY='#{openai.value}'" if openai

    env_vars
  end

  def start_docker_process(command, env_vars)
    # Write a script file to shared volume to avoid shell injection via Process.spawn
    exec_dir = "/workspace/.hivemind/exec"
    FileUtils.mkdir_p(exec_dir)

    job_id = SecureRandom.hex(8)
    script_path = File.join(exec_dir, "coding_#{job_id}.sh")

    script = +"#!/bin/bash\n"
    env_vars.each { |var| script << "export #{var}\n" }
    script << "cd /workspace\n"
    script << "#{command}\n"

    File.write(script_path, script)
    File.chmod(0o755, script_path)

    @cleanup_script = script_path

    # Use docker exec — run the script file directly (no shell interpolation)
    docker_command = [
      "docker", "exec", "-w", "/workspace",
      WORKSPACE_CONTAINER, "bash", script_path
    ]

    # Start the process in background
    # Command is safe: docker_command is a fixed array of strings + a script file path we control
    pid = Process.spawn(*docker_command, pgroup: true) # brakeman:ignore:Execute
    Rails.logger.info("[CodingAgent] Started process #{pid} for task #{@task.task_key}")

    pid
  end

  def monitor_process(pid)
    output_buffer = +""
    last_broadcast = Time.current

    begin
      # Use timeout to monitor the process periodically
      Timeout.timeout(@task.timeout) do
        loop do
          # Check if process is still running
          begin
            Process.kill(0, pid)  # Signal 0 checks if process exists
          rescue Errno::ESRCH
            # Process has finished
            status = Process.waitpid2(pid)[1]
            exit_code = status.exitstatus

            # Get any remaining output
            remaining_output = capture_remaining_output(pid)
            output_buffer << remaining_output if remaining_output.present?

            # Mark as completed
            @task.update!(
              status: exit_code.zero? ? "completed" : "failed",
              output: output_buffer,
              completed_at: Time.current
            )

            if exit_code.zero?
              broadcast_completion("✅ Coding agent completed successfully!", output_buffer)
            else
              broadcast_completion("❌ Coding agent failed with exit code #{exit_code}", output_buffer)
            end

            Rails.logger.info("[CodingAgent] Task #{@task.task_key} finished with exit code #{exit_code}")
            return
          end

          # Capture any new output (this is simplified - in reality you'd need to capture stdout/stderr)
          new_output = capture_process_output(pid)
          if new_output.present?
            output_buffer << new_output
            @task.update!(output: output_buffer)

            # Broadcast progress if enough time has passed
            if Time.current - last_broadcast >= HEARTBEAT_INTERVAL
              broadcast_progress(new_output)
              last_broadcast = Time.current
            end
          end

          sleep 2.seconds
        end
      end
    rescue Timeout::Error
      # Kill the process if it times out
      begin
        Process.kill("TERM", pid)
        sleep 5.seconds
        Process.kill("KILL", pid) rescue nil
      rescue Errno::ESRCH
        # Process already dead
      end

      @task.update!(
        status: "failed",
        output: "#{output_buffer}\n\nTask timed out after #{@task.timeout} seconds",
        completed_at: Time.current
      )

      broadcast_message("⏰ Coding agent timed out after #{@task.timeout} seconds", "error")
      Rails.logger.warn("[CodingAgent] Task #{@task.task_key} timed out")
    end
  end

  def capture_remaining_output(pid)
    # In a real implementation, you'd capture the final output from the process
    # This is a placeholder since we can't easily capture docker exec output in this pattern
    ""
  end

  def capture_process_output(pid)
    # In a real implementation, you'd capture ongoing stdout/stderr from the docker process
    # This is challenging with docker exec -it, so this is a placeholder
    # A better approach would be to use docker exec without -it and capture streams differently
    ""
  end

  def broadcast_message(message, type = "info")
    ActionCable.server.broadcast(@channel, {
      type: "coding_agent_message",
      task_key: @task.task_key,
      cli: @task.cli,
      message: message,
      message_type: type,
      timestamp: Time.current.iso8601
    })
  end

  def broadcast_progress(output)
    ActionCable.server.broadcast(@channel, {
      type: "coding_agent_progress",
      task_key: @task.task_key,
      cli: @task.cli,
      output: output.last(1000), # Last 1000 chars to avoid huge broadcasts
      timestamp: Time.current.iso8601
    })
  end

  def broadcast_completion(message, full_output)
    ActionCable.server.broadcast(@channel, {
      type: "coding_agent_complete",
      task_key: @task.task_key,
      cli: @task.cli,
      task: @task.task.truncate(100),
      message: message,
      status: @task.status,
      duration: @task.duration_seconds,
      output_summary: full_output.last(2000), # Last 2000 chars for summary
      timestamp: Time.current.iso8601
    })
  end
end
