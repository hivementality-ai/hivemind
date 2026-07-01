# frozen_string_literal: true

require "open3"
require "timeout"
require "fileutils"

module Tools
  class ShellExecutor < BaseExecutor
    EXEC_TIMEOUT = 60
    MAX_OUTPUT = 50_000
    WORKSPACE_ROOT = "/workspace"
    EXEC_DIR = "/workspace/.hivemind/exec"
    WORKSPACE_CONTAINER = "#{ENV.fetch('COMPOSE_PROJECT_NAME', 'hivemind')}-workspace-1"

    def call
      command = input["command"].to_s.strip
      return ServiceResponse.failure(error: "No command provided") if command.empty?

      output, exit_code = execute_in_workspace(command)

      sanitized_output = output.to_s
                                .encode("UTF-8", invalid: :replace, undef: :replace, replace: " ")
                                .scrub(" ")
                                .truncate(MAX_OUTPUT)
      ServiceResponse.success(data: { output: sanitized_output, exit_code: exit_code })
    rescue Timeout::Error
      ServiceResponse.failure(error: "Command timed out after #{EXEC_TIMEOUT}s")
    rescue StandardError => e
      ServiceResponse.failure(error: "Shell execution failed: #{e.message}")
    end

    private

    def execute_in_workspace(command)
      # Write command to shared volume, execute inside workspace container
      # This gives agents full access to the workspace environment (apt, pip, npm, etc.)
      ensure_exec_dir

      job_id = SecureRandom.hex(8)
      script_path = File.join(EXEC_DIR, "#{job_id}.sh")
      output_path = File.join(EXEC_DIR, "#{job_id}.out")
      exit_path = File.join(EXEC_DIR, "#{job_id}.exit")

      # Inject GitHub token if configured
      github_token = VaultEntry.find_by(namespace: "github", key: "token")&.value
      gh_setup = github_token ? "export GH_TOKEN='#{github_token}'\nexport GITHUB_TOKEN='#{github_token}'\n" : ""

      # Write script via docker exec to avoid cross-container permission issues
      script_content = <<~BASH
        #!/bin/bash
        #{gh_setup}cd /workspace
        #{command}
      BASH

      # Write script from inside workspace container (correct uid)
      IO.popen(
        [ "docker", "exec", "-i", WORKSPACE_CONTAINER, "bash", "-c", "cat > #{script_path} && chmod 755 #{script_path}" ],
        "w"
      ) { |io| io.write(script_content) }

      stdout, stderr, status = nil, nil, nil
      output = ""
      exit_code = 1

      Timeout.timeout(EXEC_TIMEOUT) do
        # Try docker exec into workspace container first
        if docker_available?
          stdout, stderr, status = Open3.capture3(
            "docker", "exec", WORKSPACE_CONTAINER,
            "bash", "-c",
            "#{script_path} 2>&1; echo \"__HIVEMIND_EXIT__$?\""
          )

          # Parse exit code from sentinel line
          lines = stdout.to_s.lines
          if lines.last&.start_with?("__HIVEMIND_EXIT__")
            exit_code = lines.last.sub("__HIVEMIND_EXIT__", "").strip.to_i
            stdout = lines[0..-2].join
          else
            exit_code = status&.exitstatus || 1
          end

          output = stdout.to_s
          output += "\nSTDERR: #{stderr}" if stderr.present? && !status&.success?
        else
          # Fallback: run directly in shared volume (limited — no apt/pip)
          stdout, stderr, status = Open3.capture3(
            { "HOME" => WORKSPACE_ROOT, "PATH" => "/usr/local/bin:/usr/bin:/bin" },
            "bash", "-c", command,
            chdir: WORKSPACE_ROOT
          )
          exit_code = status&.exitstatus || 1
          output = stdout.to_s
          output += "\nSTDERR: #{stderr}" if stderr.present?
        end
      end

      # Cleanup via docker exec (same uid that created the files)
      Open3.capture3(
        "docker", "exec", WORKSPACE_CONTAINER,
        "bash", "-c", "rm -f #{script_path} #{output_path} #{exit_path}"
      ) rescue nil

      [ output, exit_code ]
    end

    def ensure_exec_dir
      Open3.capture3(
        "docker", "exec", WORKSPACE_CONTAINER,
        "bash", "-c", "mkdir -p #{EXEC_DIR}"
      )
    rescue StandardError
      FileUtils.mkdir_p(EXEC_DIR) rescue nil
    end

    def docker_available?
      @docker_available ||= begin
        _, _, status = Open3.capture3("docker", "info")
        status.success?
      rescue Errno::ENOENT
        false
      end
    end
  end
end
