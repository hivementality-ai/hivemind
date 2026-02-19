# frozen_string_literal: true

module Tools
  class FileReadExecutor < BaseExecutor
    MAX_SIZE = 100_000
    WORKSPACE_ROOT = "/workspace"

    def call
      path = input["path"].to_s.strip
      return ServiceResponse.failure(error: "No path provided") if path.empty?

      full_path = path.start_with?("/") ? path : File.join(WORKSPACE_ROOT, path)

      unless WorkspaceIo.file_exists?(full_path)
        return ServiceResponse.failure(error: "File not found: #{path}")
      end

      raw = WorkspaceIo.read_file(full_path, max_bytes: MAX_SIZE)

      content = raw.force_encoding("UTF-8")
      unless content.valid_encoding?
        content = raw.encode("UTF-8", "ASCII-8BIT", invalid: :replace, undef: :replace, replace: "")
                     .gsub(/[^[:print:]\s]/, "")
        if content.strip.length < 50
          return ServiceResponse.failure(error: "File appears to be binary (#{File.extname(full_path)}). Try the .extracted.txt version if available, or use a different tool to process this file type.")
        end
      end

      ServiceResponse.success(data: { output: content, exit_code: 0 })
    rescue StandardError => e
      ServiceResponse.failure(error: "Read failed: #{e.message}")
    end
  end
end
