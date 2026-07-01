# frozen_string_literal: true

require "open3"
require "fileutils"

class CodingAgentJob < ApplicationJob
  queue_as :agents

  WORKSPACE_CONTAINER = "#{ENV.fetch('COMPOSE_PROJECT_NAME', 'hivemind')}-workspace-1"
  EXEC_DIR = "/workspace/.hivemind/exec"
  BROADCAST_INTERVAL = 5 # seconds between progress broadcasts

  def perform(coding_agent_task_id)
    @task = CodingAgentTask.find(coding_agent_task_id)
    @channel = resolve_channel
    @task.update!(status: "running", started_at: Time.current)

    broadcast_message("🤖 Starting #{@task.cli} coding agent...")

    command = build_cli_command(@task.cli, @task.task, @task.model)
    env_vars = build_env_vars

    # Write script + run via docker exec, capturing output to a log file on the shared volume
    job_id = SecureRandom.hex(8)
    @script_path = File.join(EXEC_DIR, "coding_#{job_id}.sh")
    @log_path = File.join(EXEC_DIR, "coding_#{job_id}.log")
    @pid_path = File.join(EXEC_DIR, "coding_#{job_id}.pid")
    @exit_path = File.join(EXEC_DIR, "coding_#{job_id}.exit")

    FileUtils.mkdir_p(EXEC_DIR)

    # Build script that logs output and writes exit code
    script = +"#!/bin/bash\n"
    env_vars.each { |k, v| script << "export #{k}='#{v}'\n" }
    script << "cd /workspace\n"
    script << "#{command} > #{@log_path} 2>&1\n"
    script << "echo $? > #{@exit_path}\n"

    File.write(@script_path, script)
    File.chmod(0o755, @script_path)

    # Run via docker exec in background using bash
    docker_cmd = [
      "docker", "exec", "-w", "/workspace",
      WORKSPACE_CONTAINER, "bash", @script_path
    ]

    # Start in a thread so we can monitor the log file concurrently
    exec_thread = Thread.new do
      Open3.capture3(*docker_cmd)
    end

    @task.update!(process_info: { job_id: job_id, started_at: Time.current.iso8601 })

    # Monitor the log file and stream output
    monitor_output(exec_thread)

  rescue StandardError => e
    Rails.logger.error("[CodingAgent] Task #{@task&.task_key} failed: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    @task&.update!(status: "failed", output: "Error: #{e.message}", completed_at: Time.current)
    broadcast_message("❌ Coding agent failed: #{e.message}")
  ensure
    cleanup_files
  end

  private

  def monitor_output(exec_thread)
    output_buffer = +""
    last_broadcast = Time.current
    last_size = 0
    started = Time.current

    loop do
      # Check timeout
      if Time.current - started > @task.timeout
        kill_docker_process
        @task.update!(
          status: "failed",
          output: "#{output_buffer}\n\n⏰ Timed out after #{@task.timeout}s",
          completed_at: Time.current
        )
        broadcast_message("⏰ Coding agent timed out after #{@task.timeout}s")
        return
      end

      # Read new output from log file
      if File.exist?(@log_path)
        current_size = File.size(@log_path)
        if current_size > last_size
          new_content = File.open(@log_path, "rb") do |f|
            f.seek(last_size)
            f.read
          end
          if new_content.present?
            output_buffer << new_content
            last_size = current_size

            # Broadcast progress periodically
            if Time.current - last_broadcast >= BROADCAST_INTERVAL
              broadcast_progress(new_content)
              last_broadcast = Time.current
              # Update task output periodically (not every loop to reduce DB writes)
              @task.update!(output: output_buffer.last(100_000))
            end
          end
        end
      end

      # Check if docker exec finished
      unless exec_thread.alive?
        # Read any remaining output
        sleep 0.5 # Brief pause for final log flush
        if File.exist?(@log_path)
          remaining = File.open(@log_path, "rb") { |f| f.seek(last_size); f.read }
          output_buffer << remaining if remaining.present?
        end

        # Get exit code
        exit_code = if File.exist?(@exit_path)
                      File.read(@exit_path).strip.to_i
        else
                      1
        end

        @task.update!(
          status: exit_code.zero? ? "completed" : "failed",
          output: output_buffer.last(100_000),
          completed_at: Time.current
        )

        if exit_code.zero?
          broadcast_completion("✅ Coding agent completed!", output_buffer)
        else
          broadcast_completion("❌ Coding agent failed (exit #{exit_code})", output_buffer)
        end

        Rails.logger.info("[CodingAgent] Task #{@task.task_key} finished (exit #{exit_code}, #{@task.duration_seconds}s)")
        return
      end

      sleep 2
    end
  end

  def kill_docker_process
    # Kill any running process inside the workspace container for this script
    system("docker", "exec", WORKSPACE_CONTAINER, "pkill", "-f", File.basename(@script_path))
  rescue StandardError => e
    Rails.logger.warn("[CodingAgent] Failed to kill process: #{e.message}")
  end

  def build_cli_command(cli, task, model)
    require "shellwords"
    escaped_task = Shellwords.shellescape(task)

    case cli
    when "claude"
      cmd = "claude --dangerously-skip-permissions -p #{escaped_task}"
      cmd += " --model #{Shellwords.shellescape(model)}" if model.present?
      cmd
    when "codex"
      cmd = "codex exec --full-auto #{escaped_task}"
      cmd += " --model #{Shellwords.shellescape(model)}" if model.present?
      cmd
    when "aider"
      cmd = "aider --yes-always --message #{escaped_task}"
      cmd += " --model #{Shellwords.shellescape(model)}" if model.present?
      cmd
    else
      raise ArgumentError, "Unknown CLI: #{cli}"
    end
  end

  def build_env_vars
    keys = {}
    anthropic = VaultEntry.find_by(namespace: "provider_credentials", key: "anthropic_api_key")
    keys["ANTHROPIC_API_KEY"] = anthropic.value if anthropic
    openai = VaultEntry.find_by(namespace: "provider_credentials", key: "openai_api_key")
    keys["OPENAI_API_KEY"] = openai.value if openai
    keys
  end

  def resolve_channel
    session = @task.session
    if session.team_chat_session_id.present?
      "team_chat_#{session.team_chat_session_id}"
    else
      "session_#{session.id}"
    end
  end

  def broadcast_message(message)
    ActionCable.server.broadcast(@channel, {
      type: "coding_agent_message",
      task_key: @task.task_key,
      cli: @task.cli,
      message: message,
      timestamp: Time.current.iso8601
    })
  end

  def broadcast_progress(output)
    ActionCable.server.broadcast(@channel, {
      type: "coding_agent_progress",
      task_key: @task.task_key,
      cli: @task.cli,
      output: output.last(2000),
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
      output_summary: full_output.last(3000),
      timestamp: Time.current.iso8601
    })
  end

  def cleanup_files
    [ @script_path, @log_path, @pid_path, @exit_path ].compact.each do |path|
      File.delete(path) if File.exist?(path)
    end
  rescue StandardError => e
    Rails.logger.warn("[CodingAgent] Cleanup failed: #{e.message}")
  end
end
