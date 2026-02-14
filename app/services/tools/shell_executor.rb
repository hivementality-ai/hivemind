# frozen_string_literal: true

require "open3"
require "timeout"
require "fileutils"

module Tools
  class ShellExecutor < BaseExecutor
    EXEC_TIMEOUT = 30
    MAX_OUTPUT = 50_000
    WORKSPACE_ROOT = "/workspace"
    EXEC_DIR = "/workspace/.hivemind/exec"

    def call
      command = input["command"].to_s.strip
      return ServiceResponse.failure(error: "No command provided") if command.empty?

      # Write command to a script file in workspace volume, then exec in workspace container
      # Both sidekiq and workspace containers share the workspace_data volume
      job_id = SecureRandom.hex(8)
      script_path = File.join(EXEC_DIR, "#{job_id}.sh")
      output_path = File.join(EXEC_DIR, "#{job_id}.out")
      exit_path = File.join(EXEC_DIR, "#{job_id}.exit")

      FileUtils.mkdir_p(EXEC_DIR)

      # Write script
      File.write(script_path, "#!/bin/bash\ncd /workspace\n#{command}\n")
      File.chmod(0o755, script_path)

      # Execute via docker exec (if docker available) or directly in workspace container
      # The workspace container runs Ubuntu — we can use `docker exec`
      # But if no docker CLI, fall back to executing locally in the shared volume
      output, exit_code = execute_command(command)

      # Cleanup
      [script_path, output_path, exit_path].each { |f| File.delete(f) if File.exist?(f) }

      ServiceResponse.success(data: { output: output.to_s.truncate(MAX_OUTPUT), exit_code: exit_code })
    rescue Timeout::Error
      ServiceResponse.failure(error: "Command timed out after #{EXEC_TIMEOUT}s")
    rescue StandardError => e
      ServiceResponse.failure(error: "Shell execution failed: #{e.message}")
    end

    private

    def execute_command(command)
      # Try to run in workspace directory
      stdout, stderr, status = nil, nil, nil

      Timeout.timeout(EXEC_TIMEOUT) do
        stdout, stderr, status = Open3.capture3(
          { "HOME" => WORKSPACE_ROOT, "PATH" => "/usr/local/bin:/usr/bin:/bin" },
          "bash", "-c", command,
          chdir: WORKSPACE_ROOT
        )
      end

      output = stdout.to_s
      output += "\nSTDERR: #{stderr}" if stderr.present?

      [output, status&.exitstatus || 1]
    end
  end
end
