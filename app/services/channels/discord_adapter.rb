# frozen_string_literal: true

module Channels
  class DiscordAdapter < BaseAdapter
    BASE_URL = "https://discord.com/api/v10"

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

      payload = { content: content }
      payload[:embeds] = options[:embeds] if options[:embeds]

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

    def discord_request(method, path, body, token)
      conn = Faraday.new(url: BASE_URL) do |f|
        f.request :json if body
        f.adapter Faraday.default_adapter
      end

      conn.run_request(method, path, body&.to_json, {
        "Authorization" => "Bot #{token}",
        "Content-Type" => "application/json"
      })
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
  end
end
