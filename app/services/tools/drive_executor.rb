# frozen_string_literal: true

require "open3"
require "json"

module Tools
  class DriveExecutor < BaseExecutor
    # Google Drive via rclone. No API key needed — rclone handles its own OAuth.
    #
    # Setup: `rclone config` → name it "gdrive" → pick Google Drive → authorize
    # Or set RCLONE_CONFIG_PATH to a pre-configured rclone.conf
    #
    # The remote name is configurable via vault: google/drive_remote (default: "gdrive")

    REMOTE = "gdrive"

    def call
      action = input["action"].to_s.strip

      case action
      when "list", "ls"
        list_files
      when "search"
        search_files
      when "read", "cat"
        read_file
      when "download"
        download_file
      when "upload"
        upload_file
      when "mkdir"
        make_directory
      when "delete", "rm"
        delete_file
      when "info"
        file_info
      when "status"
        check_status
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Supported: list, search, read, download, upload, mkdir, delete, info, status")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Drive error: #{e.message}")
    end

    private

    def list_files
      path = input["path"].to_s.strip.presence || ""
      limit = (input["limit"] || 20).to_i.clamp(1, 100)

      stdout, stderr, status = rclone("lsjson", "#{remote}:#{path}", "--no-modtime")
      return rclone_error(stderr) unless status.success?

      files = JSON.parse(stdout)
      files = files.first(limit)

      if files.any?
        output = files.map do |f|
          type = f["IsDir"] ? "📁" : "📄"
          size = f["IsDir"] ? "" : " (#{human_size(f["Size"])})"
          "#{type} #{f["Path"]}#{size}"
        end.join("\n")
        ServiceResponse.success(data: { output: "Files in /#{path}:\n#{output}", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "No files in /#{path}", exit_code: 0 })
      end
    end

    def search_files
      query = input["query"].to_s.strip
      return ServiceResponse.failure(error: "No query provided") if query.empty?

      # rclone doesn't have native search, so we list recursively and filter
      stdout, stderr, status = rclone("lsjson", "#{remote}:", "--recursive", "--no-modtime", "--files-only")
      return rclone_error(stderr) unless status.success?

      files = JSON.parse(stdout)
      matches = files.select { |f| f["Path"].downcase.include?(query.downcase) }.first(20)

      if matches.any?
        output = matches.map { |f| "📄 #{f["Path"]} (#{human_size(f["Size"])})" }.join("\n")
        ServiceResponse.success(data: { output: "Found #{matches.size} files matching '#{query}':\n#{output}", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "No files matching '#{query}'", exit_code: 0 })
      end
    end

    def read_file
      path = input["path"].to_s.strip
      return ServiceResponse.failure(error: "No path provided") if path.empty?

      stdout, stderr, status = rclone("cat", "#{remote}:#{path}")
      return rclone_error(stderr) unless status.success?

      content = stdout.truncate(30_000)
      ServiceResponse.success(data: { output: "Content of #{path}:\n\n#{content}", exit_code: 0 })
    end

    def download_file
      path = input["path"].to_s.strip
      dest = input["dest"].to_s.strip.presence || "/workspace/downloads/"
      return ServiceResponse.failure(error: "No path provided") if path.empty?

      FileUtils.mkdir_p(dest)
      stdout, stderr, status = rclone("copy", "#{remote}:#{path}", dest)
      return rclone_error(stderr) unless status.success?

      filename = File.basename(path)
      ServiceResponse.success(data: { output: "Downloaded #{path} → #{dest}#{filename}", exit_code: 0 })
    end

    def upload_file
      local_path = input["local_path"].to_s.strip
      dest = input["dest"].to_s.strip.presence || ""
      return ServiceResponse.failure(error: "No local_path provided") if local_path.empty?

      stdout, stderr, status = rclone("copy", local_path, "#{remote}:#{dest}")
      return rclone_error(stderr) unless status.success?

      filename = File.basename(local_path)
      ServiceResponse.success(data: { output: "Uploaded #{filename} → Drive:/#{dest}", exit_code: 0 })
    end

    def make_directory
      path = input["path"].to_s.strip
      return ServiceResponse.failure(error: "No path provided") if path.empty?

      stdout, stderr, status = rclone("mkdir", "#{remote}:#{path}")
      return rclone_error(stderr) unless status.success?

      ServiceResponse.success(data: { output: "Created directory: #{path}", exit_code: 0 })
    end

    def delete_file
      path = input["path"].to_s.strip
      return ServiceResponse.failure(error: "No path provided") if path.empty?

      stdout, stderr, status = rclone("delete", "#{remote}:#{path}")
      return rclone_error(stderr) unless status.success?

      ServiceResponse.success(data: { output: "Deleted: #{path}", exit_code: 0 })
    end

    def file_info
      path = input["path"].to_s.strip
      return ServiceResponse.failure(error: "No path provided") if path.empty?

      # Get parent dir listing and find the file
      dir = File.dirname(path)
      name = File.basename(path)

      stdout, stderr, status = rclone("lsjson", "#{remote}:#{dir}")
      return rclone_error(stderr) unless status.success?

      files = JSON.parse(stdout)
      file = files.find { |f| f["Path"] == name }
      return ServiceResponse.failure(error: "File not found: #{path}") unless file

      output = []
      output << "Name: #{file["Path"]}"
      output << "Type: #{file["IsDir"] ? "Directory" : "File"}"
      output << "Size: #{human_size(file["Size"])}" unless file["IsDir"]
      output << "Modified: #{file["ModTime"]}" if file["ModTime"]
      output << "MimeType: #{file["MimeType"]}" if file["MimeType"]
      output << "ID: #{file["ID"]}" if file["ID"]

      ServiceResponse.success(data: { output: output.join("\n"), exit_code: 0 })
    end

    def check_status
      stdout, stderr, status = rclone("about", "#{remote}:")

      if status.success?
        ServiceResponse.success(data: { output: "Drive connected:\n#{stdout}", exit_code: 0 })
      else
        ServiceResponse.failure(error: "Drive not configured. Run `rclone config` to set up.\n#{stderr}")
      end
    end

    # ─── Helpers ───────────────────────────────────────────────────

    def rclone(*args)
      env = {}
      config_path = vault_get("google", "rclone_config_path")
      env["RCLONE_CONFIG"] = config_path if config_path

      Open3.capture3(env, "rclone", *args, timeout: 30)
    rescue Errno::ENOENT
      [ "", "rclone not installed. Install: https://rclone.org/install/", Process::Status ]
    end

    def rclone_error(stderr)
      ServiceResponse.failure(error: "rclone: #{stderr.to_s.truncate(500)}")
    end

    def remote
      @remote ||= vault_get("google", "drive_remote") || REMOTE
    end

    def human_size(bytes)
      return "0 B" unless bytes
      units = %w[B KB MB GB TB]
      i = 0
      size = bytes.to_f
      while size >= 1024 && i < units.length - 1
        size /= 1024
        i += 1
      end
      "#{size.round(1)} #{units[i]}"
    end

    def vault_get(namespace, key)
      entry = VaultEntry.find_by(namespace: namespace, key: key)
      entry&.value
    end
  end
end
