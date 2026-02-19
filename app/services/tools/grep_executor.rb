# frozen_string_literal: true

require "open3"

module Tools
  class GrepExecutor < BaseExecutor
    MAX_OUTPUT = 50_000
    DEFAULT_MAX_RESULTS = 50

    def call
      pattern = input["pattern"]&.to_s&.strip
      return ServiceResponse.failure(error: "No pattern provided") if pattern.blank?

      path = input["path"]&.to_s&.strip.presence || "/workspace"
      case_insensitive = input["case_insensitive"]
      max_results = input["max_results"]&.to_i || DEFAULT_MAX_RESULTS

      # Build grep command
      grep_cmd = build_grep_command(pattern, path, case_insensitive)

      # Execute grep via WorkspaceIo
      results = execute_grep(grep_cmd, max_results)

      ServiceResponse.success(data: { results: results, count: results.length })
    rescue StandardError => e
      ServiceResponse.failure(error: "Grep execution failed: #{e.message}")
    end

    private

    def build_grep_command(pattern, path, case_insensitive)
      cmd_parts = [ "grep", "-rn" ]
      cmd_parts << "-i" if case_insensitive
      cmd_parts << WorkspaceIo.shell_escape(pattern)
      cmd_parts << WorkspaceIo.shell_escape(path)
      cmd_parts.join(" ")
    end

    def execute_grep(grep_cmd, max_results)
      stdout, stderr, status = Open3.capture3(
        "docker", "exec", WorkspaceIo::WORKSPACE_CONTAINER, "bash", "-c", grep_cmd
      )

      # Grep returns exit code 1 when no matches found, which is not an error for us
      if !status.success? && status.exitstatus != 1
        raise "Grep command failed: #{stderr}"
      end

      # Parse grep output into structured format
      results = []
      stdout.lines.first(max_results).each do |line|
        line = line.chomp
        # Grep -rn format: filename:line_number:text
        if line =~ /^([^:]+):(\d+):(.*)$/
          results << {
            file: $1,
            line_number: $2.to_i,
            text: $3
          }
        end
      end

      results
    end
  end
end