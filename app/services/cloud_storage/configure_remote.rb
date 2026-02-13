# frozen_string_literal: true

require "open3"
require "json"
require "fileutils"

module CloudStorage
  # Creates and manages rclone remotes headlessly.
  # Users run `rclone authorize <backend>` locally, paste the token, and we create the config.
  #
  # Supported backends:
  #   - drive (Google Drive)
  #   - s3 (Amazon S3 / compatible)
  #   - dropbox
  #   - onedrive (Microsoft OneDrive)
  #   - b2 (Backblaze B2)
  #   - sftp
  #
  class ConfigureRemote
    RCLONE_CONFIG_DIR = "/rails/storage/rclone"
    RCLONE_CONFIG_PATH = "#{RCLONE_CONFIG_DIR}/rclone.conf"

    BACKENDS = {
      "drive" => { name: "Google Drive", rclone_type: "drive", needs_token: true },
      "s3" => { name: "Amazon S3", rclone_type: "s3", needs_token: false },
      "dropbox" => { name: "Dropbox", rclone_type: "dropbox", needs_token: true },
      "onedrive" => { name: "OneDrive", rclone_type: "onedrive", needs_token: true },
      "b2" => { name: "Backblaze B2", rclone_type: "b2", needs_token: false },
      "sftp" => { name: "SFTP", rclone_type: "sftp", needs_token: false }
    }.freeze

    def initialize(backend:, remote_name:, token: nil, params: {})
      @backend = backend
      @remote_name = remote_name.to_s.strip.gsub(/[^a-zA-Z0-9_-]/, "")
      @token = token
      @params = params
    end

    def call
      return failure(error: "Unknown backend: #{@backend}") unless BACKENDS.key?(@backend)
      return failure(error: "Remote name is required") if @remote_name.empty?

      FileUtils.mkdir_p(RCLONE_CONFIG_DIR)

      case @backend
      when "drive"
        configure_drive
      when "s3"
        configure_s3
      when "dropbox"
        configure_dropbox
      when "onedrive"
        configure_onedrive
      when "b2"
        configure_b2
      when "sftp"
        configure_sftp
      end
    end

    def self.list_remotes
      config_path = RCLONE_CONFIG_PATH
      return [] unless File.exist?(config_path)

      stdout, _, status = Open3.capture3("rclone", "listremotes", "--config", config_path)
      return [] unless status.success?

      stdout.strip.split("\n").map { |r| r.chomp(":") }
    end

    def self.remote_info(remote_name)
      config_path = RCLONE_CONFIG_PATH
      stdout, _, status = Open3.capture3("rclone", "about", "#{remote_name}:", "--config", config_path, "--json")
      return nil unless status.success?

      JSON.parse(stdout) rescue nil
    end

    def self.delete_remote(remote_name)
      config_path = RCLONE_CONFIG_PATH
      _, _, status = Open3.capture3("rclone", "config", "delete", remote_name, "--config", config_path)
      status.success?
    end

    def self.config_path
      RCLONE_CONFIG_PATH
    end

    private

    def configure_drive
      return failure(error: "Token required — run `rclone authorize \"drive\"` locally and paste the result") if @token.blank?

      rclone_create("drive", token: @token, scope: "drive")
    end

    def configure_dropbox
      return failure(error: "Token required — run `rclone authorize \"dropbox\"` locally and paste the result") if @token.blank?

      rclone_create("dropbox", token: @token)
    end

    def configure_onedrive
      return failure(error: "Token required — run `rclone authorize \"onedrive\"` locally and paste the result") if @token.blank?

      rclone_create("onedrive", token: @token)
    end

    def configure_s3
      provider = @params[:provider] || "AWS"
      access_key = @params[:access_key_id].to_s.strip
      secret_key = @params[:secret_access_key].to_s.strip
      region = @params[:region] || "us-east-1"
      endpoint = @params[:endpoint].to_s.strip

      return failure(error: "access_key_id and secret_access_key required") if access_key.empty? || secret_key.empty?

      args = [
        "rclone", "config", "create", @remote_name, "s3",
        "provider", provider,
        "access_key_id", access_key,
        "secret_access_key", secret_key,
        "region", region,
        "--config", RCLONE_CONFIG_PATH
      ]
      args += ["endpoint", endpoint] if endpoint.present?

      run_rclone(args)
    end

    def configure_b2
      account = @params[:account].to_s.strip
      key = @params[:key].to_s.strip

      return failure(error: "account and key required") if account.empty? || key.empty?

      run_rclone([
        "rclone", "config", "create", @remote_name, "b2",
        "account", account,
        "key", key,
        "--config", RCLONE_CONFIG_PATH
      ])
    end

    def configure_sftp
      host = @params[:host].to_s.strip
      user = @params[:user].to_s.strip
      port = @params[:port] || "22"

      return failure(error: "host and user required") if host.empty? || user.empty?

      args = [
        "rclone", "config", "create", @remote_name, "sftp",
        "host", host,
        "user", user,
        "port", port.to_s,
        "--config", RCLONE_CONFIG_PATH
      ]

      pass = @params[:pass].to_s.strip
      key_file = @params[:key_file].to_s.strip
      args += ["pass", rclone_obscure(pass)] if pass.present?
      args += ["key_file", key_file] if key_file.present?

      run_rclone(args)
    end

    # ─── Helpers ───────────────────────────────────────────────────

    def rclone_create(type, token:, **extra)
      args = [
        "rclone", "config", "create", @remote_name, type,
        "--config", RCLONE_CONFIG_PATH
      ]
      extra.each { |k, v| args += [k.to_s, v.to_s] }

      # Write token directly to config after creation
      result = run_rclone(args)
      return result unless result[:success] != false

      # Inject token into the config file
      inject_token(@remote_name, @token)
    end

    def inject_token(remote_name, token)
      return failure(error: "Config file not found") unless File.exist?(RCLONE_CONFIG_PATH)

      config = File.read(RCLONE_CONFIG_PATH)

      # Find the section and add/replace the token line
      section_re = /^\[#{Regexp.escape(remote_name)}\]/
      unless config.match?(section_re)
        return failure(error: "Remote section not found in config")
      end

      # Remove existing token line if present
      config.gsub!(/^(token\s*=\s*.*)$/, "")

      # Add token after the section header
      config.sub!(section_re, "[#{remote_name}]\ntoken = #{token}")

      # Clean up double newlines
      config.gsub!(/\n{3,}/, "\n\n")

      File.write(RCLONE_CONFIG_PATH, config)

      success(data: { remote: remote_name, message: "Remote '#{remote_name}' configured successfully" })
    end

    def run_rclone(args)
      stdout, stderr, status = Open3.capture3(*args)

      if status.success?
        success(data: { remote: @remote_name, message: "Remote '#{@remote_name}' configured successfully" })
      else
        failure(error: "rclone config failed: #{stderr.presence || stdout}")
      end
    end

    def rclone_obscure(password)
      stdout, _, status = Open3.capture3("rclone", "obscure", password)
      status.success? ? stdout.strip : password
    end

    def success(data:)
      { success: true }.merge(data)
    end

    def failure(error:)
      { success: false, error: error }
    end
  end
end
