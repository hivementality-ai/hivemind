# frozen_string_literal: true

require "open3"
require "timeout"
require "fileutils"
require "shellwords"

module Tools
  class CustomScriptExecutor < BaseExecutor
    EXEC_TIMEOUT = 60
    MAX_OUTPUT = 50_000
    WORKSPACE_ROOT = "/workspace"

    def call
      template = config["script_template"].to_s.strip
      return ServiceResponse.failure(error: "No script template configured for this tool") if template.empty?

      # Interpolate {{param}} placeholders with shell-escaped input values
      command = interpolate_template(template)

      output, exit_code = execute_command(command)

      if exit_code == 0
        ServiceResponse.success(data: { output: output.to_s.truncate(MAX_OUTPUT), exit_code: exit_code })
      else
        ServiceResponse.failure(
          error: "Script exited with code #{exit_code}",
          data: { output: output.to_s.truncate(MAX_OUTPUT), exit_code: exit_code }
        )
      end
    rescue Timeout::Error
      ServiceResponse.failure(error: "Script timed out after #{EXEC_TIMEOUT}s")
    rescue StandardError => e
      ServiceResponse.failure(error: "Script execution failed: #{e.message}")
    end

    private

    def interpolate_template(template)
      result = template.dup

      # Replace {{param_name}} with shell-escaped input values
      result.gsub!(/\{\{(\w+)\}\}/) do
        param_name = Regexp.last_match(1)
        value = input[param_name] || input[param_name.to_sym]
        if value.nil?
          "" # Missing params become empty string
        else
          Shellwords.escape(value.to_s)
        end
      end

      result
    end

    def execute_command(command)
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
