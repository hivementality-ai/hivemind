# frozen_string_literal: true

require "net/http"
require "json"

module Channels
  class SlackAdapter < BaseAdapter
    BASE_URL = "https://slack.com/api"
    MAX_FILE_SIZE = 20.gigabytes # Slack's file size limit

    def receive(message)
      payload = message.deep_symbolize_keys

      # Handle URL verification challenge
      if payload[:type] == "url_verification"
        return ServiceResponse.success(data: { challenge: payload[:challenge] })
      end

      # Handle event callbacks
      event = payload[:event]
      return ServiceResponse.success(data: { skipped: true }) unless event
      return ServiceResponse.success(data: { skipped: true }) if event[:bot_id] # Ignore bot messages

      # Extract bot_user_id for routing assistance
      metadata = {
        channel_id: event[:channel],
        thread_ts: event[:thread_ts],
        event_type: event[:type],
        team_id: payload[:team_id]
      }

      # Add bot_user_id if available from authorization headers
      if payload.dig(:authorizations, 0, :user_id)
        metadata[:bot_user_id] = payload.dig(:authorizations, 0, :user_id)
      end

      # Handle file uploads from Slack users
      file_ids = []
      if event[:files].present? && event[:files].any?
        event[:files].each do |file|
          file_id = download_and_store_slack_file(file, event[:channel])
          file_ids << file_id if file_id
        end
      end

      inbound = log_inbound_message(
        external_id: event[:ts].to_s,
        sender: event[:user].to_s,
        content: event[:text].to_s,
        metadata: metadata,
        file_ids: file_ids
      )

      ServiceResponse.success(data: { inbound_message: inbound, file_ids: file_ids })
    rescue StandardError => e
      ServiceResponse.failure(error: "Slack receive failed: #{e.message}")
    end

    def send_message(to:, content:, agent: nil, **options)
      token = resolve_bot_token(agent)
      return ServiceResponse.failure(error: "Slack bot token not configured") unless token

      # Handle file uploads if file_path or url is provided
      if options[:file_path].present? || options[:url].present?
        return upload_file(
          to: to,
          token: token,
          agent: agent,
          content: content,
          **options
        )
      end

      body = {
        channel: to,
        text: content
      }
      body[:thread_ts] = options[:thread_ts] if options[:thread_ts]
      body[:blocks] = options[:blocks] if options[:blocks]
      body[:unfurl_links] = false if options[:no_unfurl]

      response = slack_post("chat.postMessage", body, token)

      if response["ok"]
        outbound = log_outbound_message(
          recipient: to,
          content: content,
          metadata: { ts: response["ts"], channel: response["channel"], agent_id: agent&.id }
        )
        ServiceResponse.success(data: { outbound_message: outbound, response: response })
      else
        ServiceResponse.failure(error: "Slack API: #{response["error"]}")
      end
    end

    def react(message_id:, emoji:, channel_id: nil)
      token = bot_token
      return ServiceResponse.failure(error: "Bot token not configured") unless token

      target_channel = channel_id || channel.config&.dig("default_channel_id")
      return ServiceResponse.failure(error: "No channel_id for reaction") unless target_channel

      body = {
        channel: target_channel,
        timestamp: message_id,
        name: emoji.gsub(/^:|:$/, "") # Strip colons if present
      }

      response = slack_post("reactions.add", body, token)
      response["ok"] ? ServiceResponse.success(data: {}) : ServiceResponse.failure(error: response["error"])
    end

    def verify_webhook(request)
      # In Socket Mode, events come from the connector (internal network) — no signing needed
      # Check if request is from internal Docker network (connector)
      remote_ip = request.remote_ip.to_s
      return true if remote_ip.start_with?("172.") || remote_ip == "127.0.0.1" || remote_ip == "::1"

      # External requests need signing secret verification
      signing_secret = VaultEntry.find_by(namespace: "channel_credentials", key: "slack_webhook_secret")&.value
      return true unless signing_secret

      timestamp = request.headers["X-Slack-Request-Timestamp"]
      signature = request.headers["X-Slack-Signature"]
      return false unless timestamp && signature

      return false if (Time.now.to_i - timestamp.to_i).abs > 300

      sig_basestring = "v0:#{timestamp}:#{request.raw_post}"
      expected = "v0=#{OpenSSL::HMAC.hexdigest("SHA256", signing_secret, sig_basestring)}"
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end

    private

    # Upload a file to Slack via files.upload API
    # @param to [String] Channel ID where file will be uploaded
    # @param token [String] Slack bot token
    # @param agent [Agent] Optional agent for metadata
    # @param content [String] Text to accompany file (used as initial_comment)
    # @param file_path [String] Local file path to upload
    # @param url [String] Remote URL to download and upload
    # @param title [String] Title of the file in Slack
    # @param options [Hash] Additional options (thread_ts, etc.)
    # @return [ServiceResponse]
    def upload_file(to:, token:, agent:, content:, file_path: nil, url: nil, title: nil, **options)
      # Validate that we have a file source
      return ServiceResponse.failure(error: "Either file_path or url must be provided") unless file_path.present? || url.present?

      # Download or read file
      file_data = if file_path.present?
                    read_local_file(file_path)
                  else
                    download_remote_file(url)
                  end

      return file_data if file_data.is_a?(ServiceResponse) && !file_data.success?

      file_content = file_data[:content]
      filename = file_data[:filename]

      # Validate file size
      size_check = validate_file_size(file_content.bytesize)
      return size_check if !size_check.success?

      # Determine file type if not provided
      filetype = determine_filetype(filename)

      # Prepare multipart request
      response = upload_via_multipart(
        token: token,
        channel: to,
        filename: filename,
        file_content: file_content,
        title: title,
        filetype: filetype,
        initial_comment: content,
        thread_ts: options[:thread_ts]
      )

      if response["ok"]
        outbound = log_outbound_message(
          recipient: to,
          content: "File uploaded: #{filename}",
          metadata: {
            file_id: response.dig("file", "id"),
            file_name: filename,
            file_url: response.dig("file", "permalink"),
            agent_id: agent&.id
          }
        )
        ServiceResponse.success(data: { outbound_message: outbound, response: response })
      else
        ServiceResponse.failure(error: "Slack file upload failed: #{response["error"]}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "File upload error: #{e.message}")
    end

    # Read a local file and return its content
    # @param file_path [String] Path to the file
    # @return [Hash] { content: String, filename: String } or ServiceResponse on error
    def read_local_file(file_path)
      file_path_obj = Pathname.new(file_path).expand_path

      # Security: prevent directory traversal
      return ServiceResponse.failure(error: "Invalid file path") unless file_path_obj.exist?

      if !File.file?(file_path_obj)
        return ServiceResponse.failure(error: "Path is not a file")
      end

      content = File.read(file_path_obj, mode: "rb")
      filename = File.basename(file_path_obj)

      { content: content, filename: filename }
    rescue StandardError => e
      ServiceResponse.failure(error: "Failed to read file: #{e.message}")
    end

    # Download a file from a remote URL
    # @param url [String] URL to download
    # @return [Hash] { content: String, filename: String } or ServiceResponse on error
    def download_remote_file(url)
      uri = URI(url)
      response = Net::HTTP.get_response(uri)

      unless response.is_a?(Net::HTTPSuccess)
        return ServiceResponse.failure(error: "Failed to download file: HTTP #{response.code}")
      end

      content = response.body
      filename = File.basename(uri.path)
      filename = "downloaded_file" if filename.blank?

      { content: content, filename: filename }
    rescue StandardError => e
      ServiceResponse.failure(error: "Failed to download file: #{e.message}")
    end

    # Validate file size against Slack's limits
    # @param size [Integer] File size in bytes
    # @return [ServiceResponse]
    def validate_file_size(size)
      if size > MAX_FILE_SIZE
        ServiceResponse.failure(
          error: "File too large: #{format_bytes(size)}. Max size is #{format_bytes(MAX_FILE_SIZE)}"
        )
      else
        ServiceResponse.success
      end
    end

    # Format bytes to human-readable format
    # @param bytes [Integer]
    # @return [String]
    def format_bytes(bytes)
      units = ["B", "KB", "MB", "GB"]
      size = bytes.to_f
      unit_index = 0

      while size >= 1024 && unit_index < units.length - 1
        size /= 1024
        unit_index += 1
      end

      "#{size.round(2)} #{units[unit_index]}"
    end

    # Determine Slack file type from filename
    # @param filename [String]
    # @return [String] Slack filetype or nil for auto-detection
    def determine_filetype(filename)
      extension = File.extname(filename).downcase.delete(".")

      filetype_map = {
        "png" => "png",
        "jpg" => "jpg",
        "jpeg" => "jpg",
        "gif" => "gif",
        "pdf" => "pdf",
        "txt" => "text",
        "md" => "markdown",
        "html" => "html",
        "json" => "json",
        "xml" => "xml",
        "csv" => "csv",
        "xlsx" => "excel",
        "xls" => "excel",
        "pptx" => "powerpointx",
        "ppt" => "powerpoint"
      }

      filetype_map[extension]
    end

    # Upload file via multipart/form-data to Slack
    # @param token [String] Bot token
    # @param channel [String] Channel ID
    # @param filename [String] Name of file
    # @param file_content [String] Binary content
    # @param title [String] Title in Slack
    # @param filetype [String] Slack filetype
    # @param initial_comment [String] Comment to introduce file
    # @param thread_ts [String] Optional thread timestamp
    # @return [Hash] Slack API response
    def upload_via_multipart(token:, channel:, filename:, file_content:, title:, filetype:, initial_comment:, thread_ts: nil)
      uri = URI("#{BASE_URL}/files.upload")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30 # Longer timeout for file uploads

      boundary = SecureRandom.hex(16)
      body = build_multipart_body(
        boundary: boundary,
        filename: filename,
        file_content: file_content,
        title: title,
        filetype: filetype,
        initial_comment: initial_comment,
        channel: channel,
        thread_ts: thread_ts
      )

      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      req.body = body

      response = http.request(req)
      JSON.parse(response.body)
    rescue StandardError => e
      { "ok" => false, "error" => e.message }
    end

    # Build multipart/form-data body for file upload
    # @return [String] Multipart body
    def build_multipart_body(boundary:, filename:, file_content:, title:, filetype:, initial_comment:, channel:, thread_ts: nil)
      parts = []

      # Add file
      parts << "--#{boundary}\r\n"
      parts << "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n"
      parts << "Content-Type: application/octet-stream\r\n\r\n"
      parts << file_content
      parts << "\r\n"

      # Add title
      if title.present?
        parts << "--#{boundary}\r\n"
        parts << "Content-Disposition: form-data; name=\"title\"\r\n\r\n"
        parts << title
        parts << "\r\n"
      end

      # Add filetype
      if filetype.present?
        parts << "--#{boundary}\r\n"
        parts << "Content-Disposition: form-data; name=\"filetype\"\r\n\r\n"
        parts << filetype
        parts << "\r\n"
      end

      # Add initial comment
      if initial_comment.present?
        parts << "--#{boundary}\r\n"
        parts << "Content-Disposition: form-data; name=\"initial_comment\"\r\n\r\n"
        parts << initial_comment
        parts << "\r\n"
      end

      # Add channel
      parts << "--#{boundary}\r\n"
      parts << "Content-Disposition: form-data; name=\"channels\"\r\n\r\n"
      parts << channel
      parts << "\r\n"

      # Add thread_ts if provided
      if thread_ts.present?
        parts << "--#{boundary}\r\n"
        parts << "Content-Disposition: form-data; name=\"thread_ts\"\r\n\r\n"
        parts << thread_ts.to_s
        parts << "\r\n"
      end

      # Add final boundary
      parts << "--#{boundary}--\r\n"

      parts.join
    end

    def resolve_bot_token(agent = nil)
      # Try agent-specific token first if agent provided
      if agent
        agent_channel = channel.agent_channels.find_by(agent: agent)
        if agent_channel&.has_bot_token?
          return agent_channel.bot_token
        end
      end

      # Fall back to channel-level bot token
      bot_token
    end

    def bot_token
      VaultEntry.find_by(namespace: "channel_credentials", key: "slack_bot_token")&.value
    end

    def slack_post(method, body, token)
      uri = URI("#{BASE_URL}/#{method}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 15

      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Content-Type"] = "application/json"
      req.body = body.to_json

      JSON.parse(http.request(req).body)
    rescue StandardError => e
      { "ok" => false, "error" => e.message }
    end

    def download_and_store_slack_file(file, channel_id)
      # file is a hash with: id, name, mimetype, size, permalink, etc.
      token = bot_token
      return nil unless token && file[:permalink_public]

      # Download the file from Slack
      file_data = download_file(file[:permalink_public], token)
      return nil unless file_data

      # Store as temporary file in workspace/uploads
      workspace_dir = File.join(Dir.home, ".openclaw", "workspace", "uploads")
      FileUtils.mkdir_p(workspace_dir)
      
      # Sanitize filename and store with timestamp
      safe_name = File.basename(file[:name]).gsub(/[^\w.-]/, "_")
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      filename = "slack_#{channel_id}_#{timestamp}_#{safe_name}"
      filepath = File.join(workspace_dir, filename)
      
      File.binwrite(filepath, file_data)

      # Return file info for storage
      {
        filename: filename,
        filepath: filepath,
        size: file_data.bytesize,
        mimetype: file[:mimetype],
        slack_file_id: file[:id],
        source: "slack"
      }
    rescue StandardError => e
      Rails.logger.error("Slack file download failed: #{e.message}")
      nil
    end

    def download_file(url, token)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 15
      http.read_timeout = 60

      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{token}"

      response = http.request(req)
      return nil unless response.is_a?(Net::HTTPSuccess)

      response.body
    rescue StandardError => e
      Rails.logger.error("File download failed: #{e.message}")
      nil
    end
  end
end
