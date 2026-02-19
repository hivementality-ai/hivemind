# frozen_string_literal: true

module Tools
  class FileWriteExecutor < BaseExecutor
    WORKSPACE_ROOT = "/workspace"

    def call
      path = input["path"].to_s.strip
      content = input["content"].to_s
      return ServiceResponse.failure(error: "No path provided") if path.empty?

      full_path = path.start_with?("/") ? path : File.join(WORKSPACE_ROOT, path)

      WorkspaceIo.write_file(full_path, content)

      ServiceResponse.success(data: { output: "Wrote #{content.length} bytes to #{path}", exit_code: 0 })
    rescue StandardError => e
      ServiceResponse.failure(error: "Write failed: #{e.message}")
    end
  end
end
