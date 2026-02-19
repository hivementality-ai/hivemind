# frozen_string_literal: true

require "open3"

module Tools
  class GlobExecutor < BaseExecutor
    MAX_FILES = 500
    WORKSPACE_ROOT = "/workspace"

    def call
      pattern = input["pattern"].to_s.strip
      return ServiceResponse.failure(error: "No pattern provided") if pattern.empty?

      root_path = input["path"].to_s.strip
      root_path = WORKSPACE_ROOT if root_path.empty?

      # Ensure path is absolute for workspace container
      full_path = root_path.start_with?("/") ? root_path : File.join(WORKSPACE_ROOT, root_path)

      # Check if root path exists and is a directory
      unless WorkspaceIo.file_exists?(full_path)
        return ServiceResponse.failure(error: "Path not found: #{root_path}")
      end

      unless WorkspaceIo.directory?(full_path)
        return ServiceResponse.failure(error: "Path is not a directory: #{root_path}")
      end

      # Execute find command with glob pattern
      # Use -name for simple patterns, -path for complex patterns with directories
      find_cmd = if pattern.include?("/")
        # Complex pattern with directory structure - use -path
        "find #{WorkspaceIo.shell_escape(full_path)} -path '#{pattern}' -type f | head -#{MAX_FILES}"
      else
        # Simple filename pattern - use -name
        "find #{WorkspaceIo.shell_escape(full_path)} -name '#{pattern}' -type f | head -#{MAX_FILES}"
      end

      stdout, stderr, status = Open3.capture3(
        "docker", "exec", WorkspaceIo::WORKSPACE_CONTAINER, "bash", "-c", find_cmd
      )

      unless status.success?
        return ServiceResponse.failure(error: "Find command failed: #{stderr.strip}")
      end

      # Parse results
      files = stdout.strip.split("\n").reject(&:empty?)

      # Convert absolute container paths to relative workspace paths for display
      relative_files = files.map do |file|
        if file.start_with?(WORKSPACE_ROOT)
          file[WORKSPACE_ROOT.length..-1].sub(/^\//, "")
        else
          file
        end
      end

      output = if relative_files.empty?
        "No files found matching pattern: #{pattern}"
      else
        count_msg = relative_files.length >= MAX_FILES ? " (limited to #{MAX_FILES})" : ""
        "Found #{relative_files.length} file(s)#{count_msg}:\n" + relative_files.join("\n")
      end

      ServiceResponse.success(data: {
        output: output,
        exit_code: 0,
        files: relative_files,
        count: relative_files.length
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Glob search failed: #{e.message}")
    end
  end
end
