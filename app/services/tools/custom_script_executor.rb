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

      secrets = resolve_secrets
      return ServiceResponse.failure(error: secrets[:error]) if secrets[:error]

      output, exit_code = execute_command(command, secrets[:env])
      output = redact(output, secrets[:env].values)

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

    # Resolves the tool's vault references into environment variables for the script.
    def resolve_secrets
      env = {}
      (config["secret_refs"] || {}).each do |env_name, reference|
        result = Vault::Reference.resolve(reference, agent: agent)
        return { error: "Could not read secret #{env_name}: #{result.error}" } unless result.success?

        env[env_name.to_s] = result.data[:value].to_s
      end
      { env: env }
    end

    def redact(output, values)
      values.select { |value| value.length >= 4 }.reduce(output.to_s) { |text, value| text.gsub(value, "[REDACTED]") }
    end

    def execute_command(command, secret_env = {})
      stdout, stderr, status = nil, nil, nil

      Timeout.timeout(EXEC_TIMEOUT) do
        stdout, stderr, status = Open3.capture3(
          { "HOME" => WORKSPACE_ROOT, "PATH" => "/usr/local/bin:/usr/bin:/bin" }.merge(secret_env),
          "bash", "-c", command,
          chdir: WORKSPACE_ROOT
        )
      end

      output = stdout.to_s
      output += "\nSTDERR: #{stderr}" if stderr.present?

      [ output, status&.exitstatus || 1 ]
    end
  end
end
