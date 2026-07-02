# frozen_string_literal: true

require "net/http"
require "json"
require "pathname"

module Channels
  class DiscordAdapter < BaseAdapter
    BASE_URL = "https://discord.com/api/v10"
    MAX_FILE_SIZE = 25.megabytes # Discord's file size limit (Nitro: 100MB, but bots get 25MB)

    def receive(message)
      payload = message.deep_symbolize_keys

      # Handle Discord interaction webhook (PING/PONG verification)
      if payload[:type] == 1 # PING
        return ServiceResponse.success(data: { pong: true })
      end

      # Handle interaction-based messages (slash commands, etc.)
      if payload[:type] == 2 # APPLICATION_COMMAND
        return receive_interaction(payload)
      end

      # Handle gateway MESSAGE_CREATE events or forwarded messages
      if payload[:content].present? || payload[:t] == "MESSAGE_CREATE"
        event_data = payload[:d] || payload
        return ServiceResponse.success(data: { skipped: true }) if event_data.dig(:author, :bot)

        # Determine if this is in a thread
        thread_id = extract_thread_id(event_data)

        inbound = log_inbound_message(
          external_id: event_data[:id].to_s,
          sender: event_data.dig(:author, :id).to_s,
          content: event_data[:content].to_s,
          metadata: {
            channel_id: event_data[:channel_id],
            guild_id: event_data[:guild_id],
            thread_id: thread_id,
            author: event_data[:author],
            message_reference: event_data[:message_reference],
            mentions: event_data[:mentions]
          }
        )

        ServiceResponse.success(data: { inbound_message: inbound })
      else
        ServiceResponse.success(data: { skipped: true })
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Discord receive failed: #{e.message}")
    end

    def send_message(to:, content:, agent: nil, **options)
      bot_token = resolve_bot_token(agent)
      return ServiceResponse.failure(error: "Bot token not configured") unless bot_token

      # Handle file uploads if file_path or url is provided
      if options[:file_path].present? || options[:url].present?
        return upload_file(
          to: to,
          bot_token: bot_token,
          agent: agent,
          content: content,
          **options
        )
      end

      payload = { content: content }
      payload[:embeds] = options[:embeds] if options[:embeds]
      payload[:flags] = options[:flags] if options[:flags] # Ephemeral support (flags: 64)

      # Thread support: send to thread channel or use message_reference
      target_channel = options[:thread_id] || to
      if options[:reply_to_message_id]
        payload[:message_reference] = { message_id: options[:reply_to_message_id] }
      end

      response = discord_request(
        :post,
        "/channels/#{target_channel}/messages",
        payload,
        bot_token
      )

      if response.success?
        result = JSON.parse(response.body)

        outbound = log_outbound_message(
          recipient: to,
          content: content,
          platform_message_id: result["id"],
          metadata: {
            message_id: result["id"],
            channel_id: target_channel,
            agent_id: agent&.id,
            response: result
          }
        )

        ServiceResponse.success(data: { outbound_message: outbound, response: result })
      else
        ServiceResponse.failure(error: "Discord API error: #{response.status} #{response.body}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Discord send failed: #{e.message}")
    end

    # Send typing indicator
    def send_typing(channel_id:, agent: nil)
      bot_token = resolve_bot_token(agent)
      return ServiceResponse.failure(error: "Bot token not configured") unless bot_token

      response = discord_request(:post, "/channels/#{channel_id}/typing", nil, bot_token)
      response.success? ? ServiceResponse.success : ServiceResponse.failure(error: "Typing failed: #{response.body}")
    rescue StandardError => e
      ServiceResponse.failure(error: "Discord typing failed: #{e.message}")
    end

    # Add a reaction to a message
    def react(channel_id:, message_id:, emoji:, agent: nil)
      bot_token = resolve_bot_token(agent)
      return ServiceResponse.failure(error: "Bot token not configured") unless bot_token

      # URL-encode the emoji (for custom emoji use name:id format)
      encoded_emoji = ERB::Util.url_encode(emoji)
      response = discord_request(
        :put,
        "/channels/#{channel_id}/messages/#{message_id}/reactions/#{encoded_emoji}/@me",
        nil,
        bot_token
      )

      # 204 No Content = success for reactions
      if response.status == 204 || response.success?
        ServiceResponse.success
      else
        ServiceResponse.failure(error: "Reaction failed: #{response.status} #{response.body}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Discord react failed: #{e.message}")
    end

    # Respond to a Discord interaction (slash command, button, etc.) with ephemeral or public response
    def respond_to_interaction(interaction_id:, interaction_token:, content: nil, ephemeral: true, embeds: nil)
      payload = { type: 4 } # CHANNEL_MESSAGE_WITH_SOURCE
      payload[:data] = {}
      payload[:data][:content] = content if content.present?
      payload[:data][:embeds] = embeds if embeds.present?
      payload[:data][:flags] = 64 if ephemeral # 64 = ephemeral/private message

      # Interaction responses don't need bot token - they use interaction_id and token
      conn = Faraday.new(url: BASE_URL) do |f|
        f.request :json
        f.adapter Faraday.default_adapter
      end

      response = conn.post(
        "/interactions/#{interaction_id}/#{interaction_token}/callback",
        payload.to_json,
        { "Content-Type" => "application/json" }
      )

      if response.success? || response.status == 204
        ServiceResponse.success(data: { ephemeral: ephemeral })
      else
        ServiceResponse.failure(error: "Interaction response failed: #{response.status} #{response.body}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Discord interaction response failed: #{e.message}")
    end

    # Build a Discord embed object for rich message formatting
    # @param title [String] Embed title
    # @param description [String] Embed description/body text
    # @param color [Integer] Color as integer (e.g., 0x5865F2 for Discord blurple)
    # @param fields [Array<Hash>] Array of { name:, value:, inline: } field objects
    # @param footer [String] Footer text
    # @param thumbnail [String] Thumbnail image URL
    # @param url [String] Title hyperlink URL
    # @return [Hash] Discord embed object ready for use in send_message embeds array
    def self.build_embed(title: nil, description: nil, color: nil, fields: nil, footer: nil, thumbnail: nil, url: nil)
      embed = {}
      embed[:title] = title if title
      embed[:description] = description if description
      embed[:color] = color || 0x5865F2 # Discord blurple default
      embed[:url] = url if url
      embed[:fields] = fields if fields
      embed[:footer] = { text: footer } if footer
      embed[:thumbnail] = { url: thumbnail } if thumbnail
      embed[:timestamp] = Time.current.iso8601
      embed
    end

    # Helper to create a Discord embed (rich message)
    # @param title [String] Title of the embed
    # @param description [String] Main description
    # @param color [Integer] Color as integer (e.g., 0xFF0000 for red)
    # @param fields [Array<Hash>] Array of { name, value, inline }
    # @param footer [String] Footer text
    # @param author [String] Author name
    # @return [Hash] Embed object for Discord API
    def create_embed(title: nil, description: nil, color: nil, fields: nil, footer: nil, author: nil, url: nil, thumbnail_url: nil)
      embed = {}
      embed[:title] = title if title.present?
      embed[:description] = description if description.present?
      embed[:color] = color if color.present?
      embed[:url] = url if url.present?
      embed[:thumbnail] = { url: thumbnail_url } if thumbnail_url.present?
      embed[:fields] = fields if fields.present?
      embed[:footer] = { text: footer } if footer.present?
      embed[:author] = { name: author } if author.present?

      embed
    end

    def edit_message(message_id, content, channel_id:, agent: nil, **options)
      bot_token = resolve_bot_token(agent)
      return ServiceResponse.failure(error: "Bot token not configured") unless bot_token

      response = discord_request(
        :patch,
        "/channels/#{channel_id}/messages/#{message_id}",
        { content: content },
        bot_token
      )

      if response.success?
        ServiceResponse.success(data: { response: JSON.parse(response.body) })
      else
        ServiceResponse.failure(error: "Discord API error: #{response.status} #{response.body}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Discord edit failed: #{e.message}")
    end

    def delete_message(message_id, channel_id:, agent: nil, **options)
      bot_token = resolve_bot_token(agent)
      return ServiceResponse.failure(error: "Bot token not configured") unless bot_token

      response = discord_request(
        :delete,
        "/channels/#{channel_id}/messages/#{message_id}",
        nil,
        bot_token
      )

      if response.status == 204 || response.success?
        ServiceResponse.success
      else
        ServiceResponse.failure(error: "Discord API error: #{response.status} #{response.body}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Discord delete failed: #{e.message}")
    end

    def verify_webhook(request)
      # Discord uses Ed25519 signature verification for interaction endpoints
      signature = request.headers["X-Signature-Ed25519"]
      timestamp = request.headers["X-Signature-Timestamp"]

      # If no Discord signature headers, check if from internal network (gateway forwarding)
      unless signature && timestamp
        remote_ip = request.remote_ip.to_s
        return remote_ip.start_with?("172.") || remote_ip == "127.0.0.1" || remote_ip == "::1"
      end

      public_key = get_public_key
      return false unless public_key

      begin
        verify_key = Ed25519::VerifyKey.new([ public_key ].pack("H*"))
        verify_key.verify([ signature ].pack("H*"), timestamp + request.raw_post)
        true
      rescue Ed25519::VerifyError
        false
      end
    end

    private

    def extract_thread_id(event_data)
      # In Discord, threads are channels. If the message is in a thread,
      # the channel_id IS the thread_id. We detect threads by checking
      # if the channel type is a thread type (11 = public thread, 12 = private thread)
      # or if message_reference exists (reply chain).
      # The gateway event includes channel type info in the channel object.
      if event_data[:thread] || event_data.dig(:channel, :type).to_i.in?([ 11, 12 ])
        event_data[:channel_id]
      end
    end

    def resolve_bot_token(agent = nil)
      # Try agent-specific token first
      if agent
        agent_channel = channel.agent_channels.find_by(agent: agent)
        return agent_channel.bot_token if agent_channel&.has_bot_token?
      end

      # Fall back to channel-level default agent's token
      default_ac = channel.agent_channels.find_by(is_default: true)
      return default_ac.bot_token if default_ac&.has_bot_token?

      # Fall back to global discord bot token
      VaultEntry.find_by(namespace: "channel_credentials", key: "discord_bot_token")&.value
    end

    def get_public_key
      # Check channel config first, then vault
      channel.config&.dig("discord_public_key") ||
        VaultEntry.find_by(namespace: "channel_credentials", key: "discord_public_key")&.value
    end

    def discord_request(method, path, body, token, interaction_endpoint: false)
      conn = Faraday.new(url: BASE_URL) do |f|
        f.request :json if body
        f.adapter Faraday.default_adapter
      end

      headers = { "Content-Type" => "application/json" }
      # Interaction endpoints use the app id and token, not the bot token
      unless interaction_endpoint
        headers["Authorization"] = "Bot #{token}"
      end

      conn.run_request(method, path, body&.to_json, headers)
    end

    def receive_interaction(payload)
      # Handle slash commands / message components
      inbound = log_inbound_message(
        external_id: payload[:id].to_s,
        sender: payload.dig(:member, :user, :id).to_s,
        content: extract_interaction_content(payload),
        metadata: {
          channel_id: payload[:channel_id],
          guild_id: payload[:guild_id],
          interaction_type: payload[:type],
          interaction_data: payload[:data],
          token: payload[:token]
        }
      )

      ServiceResponse.success(data: { inbound_message: inbound, interaction: true })
    end

    def extract_interaction_content(payload)
      data = payload[:data] || {}
      if data[:name]
        # Slash command: reconstruct as text
        options = (data[:options] || []).map { |o| "#{o[:name]}:#{o[:value]}" }.join(" ")
        "/#{data[:name]} #{options}".strip
      else
        ""
      end
    end

    # Upload a file to Discord via multipart/form-data
    # @param to [String] Channel ID where file will be uploaded
    # @param bot_token [String] Discord bot token
    # @param agent [Agent] Optional agent for metadata
    # @param content [String] Text to accompany file
    # @param file_path [String] Local file path to upload
    # @param url [String] Remote URL to download and upload
    # @param options [Hash] Additional options (thread_id, etc.)
    # @return [ServiceResponse]
    def upload_file(to:, bot_token:, agent:, content:, file_path: nil, url: nil, **options)
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

      # Prepare multipart request
      response = upload_via_multipart(
        bot_token: bot_token,
        channel: to,
        filename: filename,
        file_content: file_content,
        message_content: content,
        thread_id: options[:thread_id]
      )

      if response.success?
        result = JSON.parse(response.body)
        outbound = log_outbound_message(
          recipient: to,
          content: "File uploaded: #{filename}",
          metadata: {
            message_id: result["id"],
            file_name: filename,
            channel_id: to,
            agent_id: agent&.id
          }
        )
        ServiceResponse.success(data: { outbound_message: outbound, response: result })
      else
        ServiceResponse.failure(error: "Discord file upload failed: #{response.status} #{response.body}")
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

    # Upload file via multipart form data
    # Discord API expects: form-data with 'payload_json' and 'files[0]'
    # @return [Net::HTTPResponse]
    def upload_via_multipart(bot_token:, channel:, filename:, file_content:, message_content: nil, thread_id: nil)
      url = "#{BASE_URL}/channels/#{thread_id || channel}/messages"
      uri = URI(url)

      Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        request = Net::HTTP::Post.new(uri.path)
        request["Authorization"] = "Bot #{bot_token}"

        # Build multipart body
        boundary = "----DiscordFormBoundary#{SecureRandom.hex(16)}"
        body = build_multipart_body(
          boundary: boundary,
          message_content: message_content,
          filename: filename,
          file_content: file_content
        )

        request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        request.body = body

        http.request(request)
      end
    end

    # Determine MIME content type from filename
    def determine_content_type(filename)
      ext = File.extname(filename).downcase
      {
        ".png" => "image/png",
        ".jpg" => "image/jpeg",
        ".jpeg" => "image/jpeg",
        ".gif" => "image/gif",
        ".webp" => "image/webp",
        ".pdf" => "application/pdf",
        ".txt" => "text/plain",
        ".json" => "application/json",
        ".mp3" => "audio/mpeg",
        ".mp4" => "video/mp4",
        ".zip" => "application/zip"
      }[ext] || "application/octet-stream"
    end

    # Build multipart form body for file upload
    def build_multipart_body(boundary:, message_content:, filename:, file_content:)
      body = []

      # Add payload_json (Discord API requirement)
      payload = { content: message_content.presence || "File upload" }
      payload_json = JSON.generate(payload)

      body << "--#{boundary}"
      body << 'Content-Disposition: form-data; name="payload_json"'
      body << "Content-Type: application/json"
      body << ""
      body << payload_json

      # Add file
      body << "--#{boundary}"
      body << "Content-Disposition: form-data; name=\"files[0]\"; filename=\"#{filename}\""
      body << "Content-Type: #{determine_content_type(filename)}"
      body << ""
      body << file_content
      body << "--#{boundary}--"

      # Join with proper line endings
      body.join("\r\n").force_encoding("BINARY")
    end
  end
end
