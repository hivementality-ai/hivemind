# frozen_string_literal: true

require "websocket-client-simple"

module Channels
  # Manages WebSocket connections to Discord Gateway for real-time events.
  # Supports multiple concurrent connections (one per agent bot token).
  #
  # Usage:
  #   Channels::DiscordGateway.connect_all  # Connect all Discord agent bots
  #   Channels::DiscordGateway.disconnect_all
  #   Channels::DiscordGateway.status
  #
  class DiscordGateway
    GATEWAY_URL = "wss://gateway.discord.gg/?v=10&encoding=json"
    GATEWAY_INTENTS = 33281 # GUILDS (1) | GUILD_MESSAGES (512) | MESSAGE_CONTENT (32768) | DIRECT_MESSAGES (4096) (total: 1 + 512 + 4096 + 32768 = 37377... let me recalculate)
    # GUILDS = 1 << 0 = 1
    # GUILD_MESSAGES = 1 << 9 = 512
    # GUILD_MESSAGE_REACTIONS = 1 << 10 = 1024
    # DIRECT_MESSAGES = 1 << 12 = 4096
    # MESSAGE_CONTENT = 1 << 15 = 32768
    INTENTS = (1 << 0) | (1 << 9) | (1 << 10) | (1 << 12) | (1 << 15) # 38401

    class << self
      def registry
        @registry ||= Concurrent::Map.new
      end

      # Connect all Discord agent channels that have bot tokens
      def connect_all
        discord_channels = Channel.where(channel_type: "discord", enabled: true)
        discord_channels.each do |channel|
          channel.agent_channels.with_bot_token.each do |agent_channel|
            connect(agent_channel)
          end
        end
      end

      # Connect a single agent channel's bot to the Discord Gateway
      def connect(agent_channel)
        key = connection_key(agent_channel)
        existing = registry[key]

        # Don't reconnect if already connected
        if existing && existing[:status] == :connected
          Rails.logger.info("[DiscordGateway] Already connected: #{key}")
          return existing
        end

        Rails.logger.info("[DiscordGateway] Connecting: #{key}")
        connection = Connection.new(agent_channel)
        connection.start

        registry[key] = {
          connection: connection,
          agent_channel: agent_channel,
          status: :connecting,
          connected_at: nil
        }
      end

      def disconnect(agent_channel)
        key = connection_key(agent_channel)
        entry = registry.delete(key)
        entry[:connection]&.stop if entry
      end

      def disconnect_all
        registry.each_pair do |key, entry|
          Rails.logger.info("[DiscordGateway] Disconnecting: #{key}")
          entry[:connection]&.stop
        end
        registry.clear
      end

      def status
        registry.each_pair.map do |key, entry|
          {
            key: key,
            agent_id: entry[:agent_channel].agent_id,
            status: entry[:connection]&.status || :unknown,
            connected_at: entry[:connected_at]
          }
        end
      end

      def update_status(agent_channel, status, connected_at: nil)
        key = connection_key(agent_channel)
        entry = registry[key]
        return unless entry

        entry[:status] = status
        entry[:connected_at] = connected_at if connected_at
      end

      private

      def connection_key(agent_channel)
        "discord_agent_#{agent_channel.agent_id}_channel_#{agent_channel.channel_id}"
      end
    end

    # Represents a single WebSocket connection to the Discord Gateway
    class Connection
      attr_reader :status

      def initialize(agent_channel)
        @agent_channel = agent_channel
        @channel = agent_channel.channel
        @bot_token = agent_channel.bot_token
        @status = :initialized
        @heartbeat_interval = nil
        @heartbeat_thread = nil
        @last_sequence = nil
        @session_id = nil
        @resume_gateway_url = nil
        @ws = nil
        @reconnect_attempts = 0
        @max_reconnect_attempts = 5
      end

      def start
        return unless @bot_token.present?

        @status = :connecting
        connect_websocket(GATEWAY_URL)
      end

      def stop
        @status = :disconnecting
        @heartbeat_thread&.kill
        @ws&.close
        @status = :disconnected
      rescue StandardError => e
        Rails.logger.error("[DiscordGateway] Error stopping: #{e.message}")
        @status = :disconnected
      end

      private

      def connect_websocket(url)
        token = @bot_token
        connection = self

        @ws = WebSocket::Client::Simple.connect(url)

        @ws.on :open do
          Rails.logger.info("[DiscordGateway] WebSocket opened for agent #{connection.instance_variable_get(:@agent_channel).agent_id}")
        end

        @ws.on :message do |msg|
          connection.send(:handle_message, msg.data)
        end

        @ws.on :close do |e|
          Rails.logger.warn("[DiscordGateway] WebSocket closed: #{e&.inspect}")
          connection.send(:handle_disconnect)
        end

        @ws.on :error do |e|
          Rails.logger.error("[DiscordGateway] WebSocket error: #{e.message}")
        end
      rescue StandardError => e
        Rails.logger.error("[DiscordGateway] Connection failed: #{e.message}")
        @status = :error
        schedule_reconnect
      end

      def handle_message(raw_data)
        data = JSON.parse(raw_data, symbolize_names: true)
        @last_sequence = data[:s] if data[:s]

        case data[:op]
        when 10 # Hello
          handle_hello(data)
        when 11 # Heartbeat ACK
          # All good
        when 0  # Dispatch
          handle_dispatch(data)
        when 7  # Reconnect
          Rails.logger.info("[DiscordGateway] Received reconnect request")
          attempt_resume
        when 9  # Invalid Session
          resumable = data[:d]
          if resumable
            sleep(rand(1..5))
            attempt_resume
          else
            @session_id = nil
            sleep(rand(1..5))
            send_identify
          end
        end
      rescue StandardError => e
        Rails.logger.error("[DiscordGateway] Error handling message: #{e.message}")
      end

      def handle_hello(data)
        @heartbeat_interval = data.dig(:d, :heartbeat_interval)
        start_heartbeat
        if @session_id && @last_sequence
          attempt_resume
        else
          send_identify
        end
      end

      def handle_dispatch(data)
        case data[:t]
        when "READY"
          @session_id = data.dig(:d, :session_id)
          @resume_gateway_url = data.dig(:d, :resume_gateway_url)
          @status = :connected
          @reconnect_attempts = 0
          DiscordGateway.update_status(@agent_channel, :connected, connected_at: Time.current)
          Rails.logger.info("[DiscordGateway] READY — session: #{@session_id}")
        when "RESUMED"
          @status = :connected
          @reconnect_attempts = 0
          DiscordGateway.update_status(@agent_channel, :connected)
          Rails.logger.info("[DiscordGateway] RESUMED")
        when "MESSAGE_CREATE"
          handle_message_create(data[:d])
        end
      end

      def handle_message_create(event_data)
        # Skip bot messages
        return if event_data.dig(:author, :bot)

        # Forward to the adapter for processing
        adapter = Channels::Registry.adapter_for(@channel)
        result = adapter.receive(event_data.merge(t: "MESSAGE_CREATE"))

        if result.success? && result.data[:inbound_message]
          InboundMessageJob.perform_later(result.data[:inbound_message].id)
        end
      rescue StandardError => e
        Rails.logger.error("[DiscordGateway] Error processing MESSAGE_CREATE: #{e.message}")
      end

      def send_identify
        payload = {
          op: 2,
          d: {
            token: @bot_token,
            intents: INTENTS,
            properties: {
              os: "linux",
              browser: "hivemind",
              device: "hivemind"
            }
          }
        }
        send_ws(payload)
      end

      def attempt_resume
        if @session_id && @last_sequence
          payload = {
            op: 6,
            d: {
              token: @bot_token,
              session_id: @session_id,
              seq: @last_sequence
            }
          }
          send_ws(payload)
        else
          send_identify
        end
      end

      def start_heartbeat
        @heartbeat_thread&.kill
        return unless @heartbeat_interval

        @heartbeat_thread = Thread.new do
          # Jitter for first heartbeat
          sleep(@heartbeat_interval / 1000.0 * rand)

          loop do
            send_ws({ op: 1, d: @last_sequence })
            sleep(@heartbeat_interval / 1000.0)
          end
        rescue StandardError => e
          Rails.logger.error("[DiscordGateway] Heartbeat error: #{e.message}")
        end
      end

      def handle_disconnect
        return if @status == :disconnecting

        @status = :disconnected
        DiscordGateway.update_status(@agent_channel, :disconnected)
        schedule_reconnect
      end

      def schedule_reconnect
        return if @reconnect_attempts >= @max_reconnect_attempts

        @reconnect_attempts += 1
        delay = [ 2**@reconnect_attempts, 60 ].min # Exponential backoff, max 60s

        Rails.logger.info("[DiscordGateway] Reconnecting in #{delay}s (attempt #{@reconnect_attempts})")

        Thread.new do
          sleep(delay)
          url = @resume_gateway_url || GATEWAY_URL
          connect_websocket(url)
        end
      end

      def send_ws(data)
        @ws&.send(data.to_json)
      rescue StandardError => e
        Rails.logger.error("[DiscordGateway] WebSocket send error: #{e.message}")
      end
    end
  end
end
