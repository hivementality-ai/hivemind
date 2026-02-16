# frozen_string_literal: true

module Tools
  class PdfReadExecutor < BaseExecutor
    WORKSPACE_ROOT = "/workspace"
    SCRIPT_PATH = Rails.root.join("lib/scripts/pdf_extract.py").to_s
    MAX_OUTPUT = 100_000

    def call
      action = input["action"] || "read"

      case action
      when "read"     then read_pdf
      when "metadata" then read_metadata
      when "tables"   then read_tables
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Use: read, metadata, tables")
      end
    end

    private

    def read_pdf
      path = resolve_path
      return path if path.is_a?(ServiceResponse) # error

      pages = input["pages"] # e.g., "1-5" or "3"
      format = input["format"] || "text" # "text" or "markdown"

      cmd = [ "python3", SCRIPT_PATH, path ]
      cmd += [ "--pages", pages.to_s ] if pages.present?
      cmd += [ "--format", format ] if format == "markdown"

      execute_command(cmd)
    end

    def read_metadata
      path = resolve_path
      return path if path.is_a?(ServiceResponse)

      cmd = [ "python3", SCRIPT_PATH, path, "--metadata" ]
      execute_command(cmd)
    end

    def read_tables
      path = resolve_path
      return path if path.is_a?(ServiceResponse)

      cmd = [ "python3", SCRIPT_PATH, path, "--tables" ]
      page = input["page"]
      cmd += [ "--table-page", page.to_s ] if page.present?

      execute_command(cmd)
    end

    def resolve_path
      raw = input["path"].to_s.strip
      return ServiceResponse.failure(error: "No path provided") if raw.empty?

      full = raw.start_with?("/") ? raw : File.join(WORKSPACE_ROOT, raw)

      unless full.start_with?(WORKSPACE_ROOT) || full.start_with?(Rails.root.to_s)
        return ServiceResponse.failure(error: "Access denied: path must be within /workspace")
      end

      unless File.exist?(full)
        return ServiceResponse.failure(error: "File not found: #{raw}")
      end

      full
    end

    def execute_command(cmd)
      stdout, stderr, status = Open3.capture3(*cmd)

      if status.success?
        output = stdout.truncate(MAX_OUTPUT)
        ServiceResponse.success(data: { output: output, exit_code: 0 })
      else
        error = stderr.presence || "PDF extraction failed"
        ServiceResponse.failure(error: error.truncate(500))
      end
    end
  end
end
