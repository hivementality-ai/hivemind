# frozen_string_literal: true

require "open3"
require "json"

module Tools
  class CloudStorageExecutor < BaseExecutor
    # General cloud storage via rclone — works with any configured remote
    # (Google Drive, S3, Dropbox, OneDrive, B2, SFTP, etc.)
    #
    # Actions: remotes, list, search, read, download, upload, sync, mkdir, delete, info, about

    RCLONE_CONFIG = CloudStorage::ConfigureRemote::RCLONE_CONFIG_PATH
    TIMEOUT = 60

    def call
      action = input["action"].to_s.strip

      case action
      when "remotes"
        list_remotes
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
      when "sync"
        sync_directory
      when "copy"
        copy_files
      when "mkdir"
        make_directory
      when "delete", "rm"
        delete_path
      when "info"
        file_info
      when "about"
        remote_about
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Supported: remotes, list, search, read, download, upload, sync, copy, mkdir, delete, info, about")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Cloud storage error: #{e.message}")
    end

    private

    def list_remotes
      remotes = CloudStorage::ConfigureRemote.list_remotes
      if remotes.any?
        output = remotes.map { |r| "☁️  #{r}" }.join("\n")
        ServiceResponse.success(data: { output: "Configured remotes:\n#{output}", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "No remotes configured. Set them up at /integrations", exit_code: 0 })
      end
    end

    def list_files
      remote = resolve_remote
      return remote if remote.is_a?(ServiceResponse)

      path = input["path"].to_s.strip
      limit = (input["limit"] || 20).to_i.clamp(1, 100)

      stdout, stderr, status = rclone("lsjson", "#{remote}:#{path}", "--no-modtime")
      return rclone_error(stderr) unless status.success?

      files = JSON.parse(stdout).first(limit)

      if files.any?
        output = files.map do |f|
          icon = f["IsDir"] ? "📁" : "📄"
          size = f["IsDir"] ? "" : " (#{human_size(f["Size"])})"
          "#{icon} #{f["Path"]}#{size}"
        end.join("\n")
        ServiceResponse.success(data: { output: "#{remote}:/#{path}\n#{output}", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "No files in #{remote}:/#{path}", exit_code: 0 })
      end
    end

    def search_files
      remote = resolve_remote
      return remote if remote.is_a?(ServiceResponse)

      query = input["query"].to_s.strip
      return ServiceResponse.failure(error: "No query provided") if query.empty?

      path = input["path"].to_s.strip
      stdout, stderr, status = rclone("lsjson", "#{remote}:#{path}", "--recursive", "--no-modtime", "--files-only")
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
      remote = resolve_remote
      return remote if remote.is_a?(ServiceResponse)

      path = input["path"].to_s.strip
      return ServiceResponse.failure(error: "No path provided") if path.empty?

      stdout, stderr, status = rclone("cat", "#{remote}:#{path}", "--head", "30000")
      return rclone_error(stderr) unless status.success?

      ServiceResponse.success(data: { output: "#{remote}:#{path}\n\n#{stdout.truncate(30_000)}", exit_code: 0 })
    end

    def download_file
      remote = resolve_remote
      return remote if remote.is_a?(ServiceResponse)

      path = input["path"].to_s.strip
      dest = input["dest"].to_s.strip.presence || "/workspace/downloads/"
      return ServiceResponse.failure(error: "No path provided") if path.empty?

      FileUtils.mkdir_p(dest)
      _, stderr, status = rclone("copy", "#{remote}:#{path}", dest)
      return rclone_error(stderr) unless status.success?

      ServiceResponse.success(data: { output: "Downloaded #{remote}:#{path} → #{dest}", exit_code: 0 })
    end

    def upload_file
      remote = resolve_remote
      return remote if remote.is_a?(ServiceResponse)

      local_path = input["local_path"].to_s.strip
      dest = input["dest"].to_s.strip.presence || ""
      return ServiceResponse.failure(error: "No local_path provided") if local_path.empty?

      _, stderr, status = rclone("copy", local_path, "#{remote}:#{dest}")
      return rclone_error(stderr) unless status.success?

      ServiceResponse.success(data: { output: "Uploaded #{File.basename(local_path)} → #{remote}:/#{dest}", exit_code: 0 })
    end

    def sync_directory
      remote = resolve_remote
      return remote if remote.is_a?(ServiceResponse)

      source = input["source"].to_s.strip
      dest = input["dest"].to_s.strip
      return ServiceResponse.failure(error: "source and dest required") if source.empty? || dest.empty?

      # Determine direction — prefix with remote: if not a local path
      src = source.include?(":") ? source : "#{remote}:#{source}"
      dst = dest.include?(":") ? dest : "#{remote}:#{dest}"

      _, stderr, status = rclone("sync", src, dst, "--progress")
      return rclone_error(stderr) unless status.success?

      ServiceResponse.success(data: { output: "Synced #{src} → #{dst}", exit_code: 0 })
    end

    def copy_files
      remote = resolve_remote
      return remote if remote.is_a?(ServiceResponse)

      source = input["source"].to_s.strip
      dest = input["dest"].to_s.strip
      return ServiceResponse.failure(error: "source and dest required") if source.empty? || dest.empty?

      src = source.include?(":") ? source : "#{remote}:#{source}"
      dst = dest.include?(":") ? dest : "#{remote}:#{dest}"

      _, stderr, status = rclone("copy", src, dst)
      return rclone_error(stderr) unless status.success?

      ServiceResponse.success(data: { output: "Copied #{src} → #{dst}", exit_code: 0 })
    end

    def make_directory
      remote = resolve_remote
      return remote if remote.is_a?(ServiceResponse)

      path = input["path"].to_s.strip
      return ServiceResponse.failure(error: "No path provided") if path.empty?

      _, stderr, status = rclone("mkdir", "#{remote}:#{path}")
      return rclone_error(stderr) unless status.success?

      ServiceResponse.success(data: { output: "Created directory: #{remote}:#{path}", exit_code: 0 })
    end

    def delete_path
      remote = resolve_remote
      return remote if remote.is_a?(ServiceResponse)

      path = input["path"].to_s.strip
      return ServiceResponse.failure(error: "No path provided") if path.empty?

      _, stderr, status = rclone("delete", "#{remote}:#{path}")
      return rclone_error(stderr) unless status.success?

      ServiceResponse.success(data: { output: "Deleted: #{remote}:#{path}", exit_code: 0 })
    end

    def file_info
      remote = resolve_remote
      return remote if remote.is_a?(ServiceResponse)

      path = input["path"].to_s.strip
      return ServiceResponse.failure(error: "No path provided") if path.empty?

      dir = File.dirname(path)
      name = File.basename(path)

      stdout, stderr, status = rclone("lsjson", "#{remote}:#{dir}")
      return rclone_error(stderr) unless status.success?

      files = JSON.parse(stdout)
      file = files.find { |f| f["Path"] == name }
      return ServiceResponse.failure(error: "Not found: #{path}") unless file

      output = []
      output << "Name: #{file["Path"]}"
      output << "Type: #{file["IsDir"] ? "Directory" : "File"}"
      output << "Size: #{human_size(file["Size"])}" unless file["IsDir"]
      output << "Modified: #{file["ModTime"]}" if file["ModTime"]
      output << "MimeType: #{file["MimeType"]}" if file["MimeType"]

      ServiceResponse.success(data: { output: output.join("\n"), exit_code: 0 })
    end

    def remote_about
      remote = resolve_remote
      return remote if remote.is_a?(ServiceResponse)

      stdout, stderr, status = rclone("about", "#{remote}:", "--json")

      if status.success?
        info = JSON.parse(stdout) rescue {}
        lines = []
        lines << "Remote: #{remote}"
        lines << "Total: #{human_size(info["total"])}" if info["total"]
        lines << "Used: #{human_size(info["used"])}" if info["used"]
        lines << "Free: #{human_size(info["free"])}" if info["free"]
        lines << "Trashed: #{human_size(info["trashed"])}" if info["trashed"]
        ServiceResponse.success(data: { output: lines.join("\n"), exit_code: 0 })
      else
        ServiceResponse.failure(error: "Could not connect to remote: #{stderr.to_s.truncate(300)}")
      end
    end

    # ─── Helpers ───────────────────────────────────────────────────

    def resolve_remote
      name = input["remote"].to_s.strip
      return name if name.present?

      # Fall back to first configured remote
      remotes = CloudStorage::ConfigureRemote.list_remotes
      if remotes.empty?
        return ServiceResponse.failure(error: "No cloud storage remotes configured. Set one up at /integrations")
      end

      remotes.first
    end

    def rclone(*args)
      env = { "RCLONE_CONFIG" => RCLONE_CONFIG }

      Timeout.timeout(TIMEOUT) do
        Open3.capture3(env, "rclone", *args)
      end
    rescue Errno::ENOENT
      ["", "rclone not installed", stub_status]
    end

    def stub_status
      Struct.new(:success?).new(false)
    end

    def rclone_error(stderr)
      ServiceResponse.failure(error: "rclone: #{stderr.to_s.truncate(500)}")
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
  end
end
