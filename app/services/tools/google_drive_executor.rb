# frozen_string_literal: true

require "open3"
require "json"
require "timeout"

module Tools
  class GoogleDriveExecutor < BaseExecutor
    TIMEOUT = 30
    MAX_OUTPUT = 50_000
    REQUIRED_SCOPE = "https://www.googleapis.com/auth/drive"

    def call
      return scope_error unless scope_granted?

      action = input["action"].to_s.strip

      case action
      when "list", "ls"
        list_files
      when "search"
        search_files
      when "get"
        get_file
      when "create"
        create_file
      when "upload"
        upload_file
      when "download"
        download_file
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Supported: list, search, get, create, upload, download")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Google Drive error: #{e.message}")
    end

    private

    def list_files
      params = input["params"] || {}
      params["pageSize"] ||= 20

      result = gws("drive", "files", "list", "--params", params.to_json)
      return result if result.is_a?(ServiceResponse) && !result.success?

      files = parse_drive_files(result)
      if files.any?
        output = files.map { |f| format_file(f) }.join("\n")
        ServiceResponse.success(data: { output: "Drive files:\n#{output}", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "No files found.", exit_code: 0 })
      end
    end

    def search_files
      query = input["query"].to_s.strip
      return ServiceResponse.failure(error: "No query provided") if query.empty?

      params = input["params"] || {}
      params["q"] = query
      params["pageSize"] ||= 20

      result = gws("drive", "files", "list", "--params", params.to_json)
      return result if result.is_a?(ServiceResponse) && !result.success?

      files = parse_drive_files(result)
      if files.any?
        output = files.map { |f| format_file(f) }.join("\n")
        ServiceResponse.success(data: { output: "Found #{files.size} file(s):\n#{output}", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "No files matching query.", exit_code: 0 })
      end
    end

    def get_file
      file_id = input["file_id"].to_s.strip
      return ServiceResponse.failure(error: "No file_id provided") if file_id.empty?

      result = gws("drive", "files", "get", file_id)
      return result if result.is_a?(ServiceResponse) && !result.success?

      data = JSON.parse(result) rescue result
      output = if data.is_a?(Hash)
        [
          "Name: #{data["name"]}",
          "ID: #{data["id"]}",
          "Type: #{data["mimeType"]}",
          ("Size: #{data["size"]} bytes" if data["size"]),
          ("Modified: #{data["modifiedTime"]}" if data["modifiedTime"]),
          ("Created: #{data["createdTime"]}" if data["createdTime"]),
          ("Web link: #{data["webViewLink"]}" if data["webViewLink"])
        ].compact.join("\n")
      else
        result
      end

      ServiceResponse.success(data: { output: output, exit_code: 0 })
    end

    def create_file
      name = input["name"].to_s.strip
      return ServiceResponse.failure(error: "No name provided") if name.empty?

      metadata = { "name" => name }
      metadata["mimeType"] = input["mime_type"] if input["mime_type"].present?
      metadata["parents"] = [ input["parent_id"] ] if input["parent_id"].present?

      result = gws("drive", "files", "create", "--json", metadata.to_json)
      return result if result.is_a?(ServiceResponse) && !result.success?

      data = JSON.parse(result) rescue result
      if data.is_a?(Hash)
        ServiceResponse.success(data: { output: "Created file: #{data["name"]} (ID: #{data["id"]})", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "Created file: #{result}", exit_code: 0 })
      end
    end

    def upload_file
      local_path = input["local_path"].to_s.strip
      return ServiceResponse.failure(error: "No local_path provided") if local_path.empty?

      metadata = {}
      metadata["name"] = input["name"] || File.basename(local_path)
      metadata["parents"] = [ input["parent_id"] ] if input["parent_id"].present?

      result = gws("drive", "files", "create", "--json", metadata.to_json, "--upload", local_path)
      return result if result.is_a?(ServiceResponse) && !result.success?

      data = JSON.parse(result) rescue result
      if data.is_a?(Hash)
        ServiceResponse.success(data: { output: "Uploaded #{metadata["name"]} (ID: #{data["id"]})", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "Uploaded #{metadata["name"]}", exit_code: 0 })
      end
    end

    def download_file
      file_id = input["file_id"].to_s.strip
      return ServiceResponse.failure(error: "No file_id provided") if file_id.empty?

      mime_type = input["mime_type"].to_s.strip.presence
      if mime_type
        result = gws("drive", "files", "export", file_id, "--params", { "mimeType" => mime_type }.to_json)
      else
        result = gws("drive", "files", "get", file_id, "--params", { "alt" => "media" }.to_json)
      end

      return result if result.is_a?(ServiceResponse) && !result.success?

      ServiceResponse.success(data: { output: result.to_s.truncate(MAX_OUTPUT), exit_code: 0 })
    end

    # ─── Helpers ───────────────────────────────────────────────────

    def gws(*args)
      GoogleWorkspace::CredentialBridge.call do |env|
        stdout, stderr, status = Timeout.timeout(TIMEOUT) do
          Open3.capture3(env, "gws", *args)
        end

        unless status.success?
          return ServiceResponse.failure(error: "gws: #{stderr.to_s.truncate(500)}")
        end

        stdout.to_s.strip
      end
    end

    def scope_granted?
      scopes = GoogleWorkspace::CredentialBridge.granted_scopes.to_s
      scopes.include?(REQUIRED_SCOPE)
    end

    def scope_error
      ServiceResponse.failure(
        error: "Google Drive access not authorized. Please grant Drive permissions at /integrations."
      )
    end

    def parse_drive_files(raw)
      data = JSON.parse(raw) rescue {}
      data["files"] || []
    end

    def format_file(file)
      type = file["mimeType"].to_s.include?("folder") ? "folder" : "file"
      icon = type == "folder" ? "📁" : "📄"
      "#{icon} #{file["name"]} (#{file["id"]}) [#{file["mimeType"]}]"
    end
  end
end
