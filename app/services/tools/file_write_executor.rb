# frozen_string_literal: true

module Tools
  class FileWriteExecutor < BaseExecutor
    WORKSPACE_ROOT = "/workspace"

    def call
      path = input["path"].to_s.strip
      content = input["content"].to_s
      return ServiceResponse.failure(error: "No path provided") if path.empty?

      full_path = path.start_with?("/") ? path : File.join(WORKSPACE_ROOT, path)

      unless full_path.start_with?(WORKSPACE_ROOT)
        return ServiceResponse.failure(error: "Access denied: path must be within /workspace")
      end

      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)

      ServiceResponse.success(data: { output: "Wrote #{content.length} bytes to #{path}", exit_code: 0 })
    rescue StandardError => e
      ServiceResponse.failure(error: "Write failed: #{e.message}")
    end
  end
end
