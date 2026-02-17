# frozen_string_literal: true

require "open3"
require "timeout"
require "fileutils"

module Tools
  class CodingAgentExecutor < BaseExecutor
    DEFAULT_TIMEOUT = 600  # 10 minutes
    MAX_TIMEOUT = 1800     # 30 minutes
    MAX_OUTPUT = 100_000   # Larger than ShellExecutor since coding agents produce more output
    WORKSPACE_ROOT = "/workspace"
    EXEC_DIR = "/workspace/.hivemind/exec"
    WORKSPACE_CONTAINER = "hivemind-workspace-1"
    ALLOWED_CLIS = %w[claude codex aider].freeze

    def call
      task = input["task"].to_s.strip
      cli = input["cli"].to_s.strip
      model = input["model"].to_s.strip
      timeout = input["timeout"].to_i

      # Validation
      return ServiceResponse.failure(error: "No task provided") if task.empty?

      cli = "claude" if cli.empty? # Default to claude
      return ServiceResponse.failure(error: "Invalid CLI. Allowed: #{ALLOWED_CLIS.join(', ')}") unless ALLOWED_CLIS.include?(cli)

      timeout = DEFAULT_TIMEOUT if timeout.zero?
      timeout = MAX_TIMEOUT if timeout > MAX_TIMEOUT

      # Security: sanitize task input to prevent shell injection
      return ServiceResponse.failure(error: "Task contains invalid characters") if task.include?("'") || task.include?("`") || task.include?("$")

      # Build CLI command
      command = build_cli_command(cli, task, model)

      # Get API keys
      env_vars = api_keys

      output, exit_code, duration = execute_coding_task(command, env_vars, timeout)

      ServiceResponse.success(data: {
        output: output.to_s.truncate(MAX_OUTPUT),
        exit_code: exit_code,
        duration_seconds: duration
      })
    rescue Timeout::Error
      ServiceResponse.failure(error: "Coding agent task timed out after #{timeout}s")
    rescue StandardError => e
      ServiceResponse.failure(error: "Coding agent execution failed: #{e.message}")
    end

    private

    def build_cli_command(cli, task, model)
      case cli
      when "claude"
        cmd = "claude --dangerously-skip-permissions -p \"#{escape_task(task)}\""
        cmd += " --model #{model}" unless model.empty?
        cmd
      when "codex"
        cmd = "codex --full-auto -q \"#{escape_task(task)}\""
        cmd += " --model #{model}" unless model.empty?
        cmd
      when "aider"
        cmd = "aider --yes-always --message \"#{escape_task(task)}\""
        cmd += " --model #{model}" unless model.empty?
        cmd
      else
        raise ArgumentError, "Unknown CLI: #{cli}"
      end
    end

    def escape_task(task)
      # Escape double quotes for shell safety while preserving the task content
      task.gsub('"', '\\"')
    end

    def api_keys
      keys = {}

      # Look up API keys from VaultEntry
      anthropic = VaultEntry.find_by(namespace: "provider_credentials", key: "anthropic_api_key")
      keys["ANTHROPIC_API_KEY"] = anthropic.value if anthropic

      openai = VaultEntry.find_by(namespace: "provider_credentials", key: "openai_api_key")
      keys["OPENAI_API_KEY"] = openai.value if openai

      keys
    end

    def execute_coding_task(command, env_vars, timeout)
      FileUtils.mkdir_p(EXEC_DIR)
      job_id = SecureRandom.hex(8)
      script_path = File.join(EXEC_DIR, "#{job_id}.sh")

      # Build script with env vars and command
      script = "#!/bin/bash\n"
      env_vars.each { |k, v| script += "export #{k}='#{v}'\n" }
      script += "cd /workspace\n#{command}\n"

      File.write(script_path, script)
      File.chmod(0o755, script_path)

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      stdout, stderr, status = Open3.capture3(
        "docker", "exec", WORKSPACE_CONTAINER,
        "bash", "-c", "timeout #{timeout} #{script_path} 2>&1"
      )

      duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time).round(1)

      # Cleanup
      File.delete(script_path) if File.exist?(script_path)

      [ stdout, status&.exitstatus || 1, duration ]
    end
  end
end
