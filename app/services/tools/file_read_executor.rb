# frozen_string_literal: true

module Tools
  class FileReadExecutor < BaseExecutor
    MAX_SIZE = 100_000
    WORKSPACE_ROOT = "/workspace"

    def call
      path = input["path"].to_s.strip
      return ServiceResponse.failure(error: "No path provided") if path.empty?

      # Resolve relative paths against workspace
      full_path = path.start_with?("/") ? path : File.join(WORKSPACE_ROOT, path)

      # Security: must be within workspace
      unless full_path.start_with?(WORKSPACE_ROOT)
        return ServiceResponse.failure(error: "Access denied: path must be within /workspace")
      end

      unless File.exist?(full_path)
        return ServiceResponse.failure(error: "File not found: #{path}")
      end

      content = File.read(full_path, MAX_SIZE)
      ServiceResponse.success(data: { output: content, exit_code: 0 })
    rescue StandardError => e
      ServiceResponse.failure(error: "Read failed: #{e.message}")
    end
  end
end
