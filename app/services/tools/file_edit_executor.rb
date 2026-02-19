# frozen_string_literal: true

module Tools
  class FileEditExecutor < BaseExecutor
    WORKSPACE_ROOT = WorkspaceIO::WORKSPACE_ROOT

    def call
      path = input["path"].to_s.strip
      old_text = input["old_text"].to_s
      new_text = input["new_text"].to_s

      return ServiceResponse.failure(error: "No path provided") if path.empty?
      return ServiceResponse.failure(error: "No old_text provided") if old_text.empty?

      full_path = resolve_path(path)

      unless WorkspaceIO.file_exists?(full_path)
        return ServiceResponse.failure(error: "File not found: #{path}")
      end

      content = WorkspaceIO.read_file(full_path)
      occurrences = content.scan(old_text).size

      if occurrences == 0
        return ServiceResponse.failure(error: "old_text not found in #{path}. Make sure it matches exactly (including whitespace).")
      elsif occurrences > 1
        return ServiceResponse.failure(error: "old_text found #{occurrences} times in #{path}. Must match exactly once for safe editing.")
      end

      new_content = content.sub(old_text, new_text)
      WorkspaceIO.write_file(full_path, new_content)

      ServiceResponse.success(data: {
        output: "Edited #{path}: replaced #{old_text.lines.size} lines with #{new_text.lines.size} lines",
        exit_code: 0
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Edit failed: #{e.message}")
    end

    private

    def resolve_path(path)
      workspace = WORKSPACE_ROOT
      expanded = File.expand_path(path, workspace)
      unless expanded.start_with?(workspace)
        raise "Path traversal denied: #{path}"
      end
      expanded
    end
  end
end
