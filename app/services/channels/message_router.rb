# frozen_string_literal: true

module Channels
  class MessageRouter
    def self.call(channel:, message:)
      new(channel: channel, message: message).call
    end

    def initialize(channel:, message:)
      @channel = channel
      @message = message
    end

    def call
      agent = route_agent
      return ServiceResponse.success(data: { agent: agent }) unless agent

      dm_result = check_dm_policy(agent)
      return dm_result if dm_result

      ServiceResponse.success(data: { agent: agent })
    rescue StandardError => e
      ServiceResponse.failure(error: "MessageRouter failed: #{e.message}")
    end

    private

    attr_reader :channel, :message

    def route_agent
      # 1. Check for @mention → match external_bot_user_id on AgentChannel
      mentioned_agent = check_mention_routing
      return mentioned_agent if mentioned_agent

      # 2. Check thread ownership → ChannelThread lookup
      thread_owner = check_thread_ownership
      return thread_owner if thread_owner

      # 3. Fall back to channel's default agent (AgentChannel.is_default)
      default_agent_channel = check_default_agent_channel
      return default_agent_channel if default_agent_channel

      # 4. Fall back to channel.config["default_agent_id"] (existing behavior)
      legacy_default = check_legacy_default
      return legacy_default if legacy_default

      # 5. Fall back to first enabled agent
      fallback_agent
    end

    def check_mention_routing
      mentioned_user_id = extract_mentioned_bot_id
      return nil unless mentioned_user_id

      agent_channel = channel.agent_channels
                            .joins(:agent)
                            .where(agents: { enabled: true })
                            .find_by(external_bot_user_id: mentioned_user_id)

      agent_channel&.agent
    end

    def check_thread_ownership
      tid = thread_id
      return nil unless tid.present?

      thread_owner = ChannelThread.thread_owner(channel: channel, thread_id: tid)
      thread_owner if thread_owner&.enabled?
    end

    def check_default_agent_channel
      default_agent_channel = channel.agent_channels
                                    .joins(:agent)
                                    .where(agents: { enabled: true })
                                    .find_by(is_default: true)

      default_agent_channel&.agent
    end

    def check_legacy_default
      agent_id = channel.config&.dig("default_agent_id")
      return nil unless agent_id.present?

      agent = Agent.find_by(id: agent_id)
      agent if agent&.enabled?
    end

    def fallback_agent
      Agent.visible.enabled.first
    end

    # --- Platform-aware mention detection ---

    def extract_mentioned_bot_id
      text = message_text
      return nil unless text.present?

      case channel.channel_type
      when "slack"
        # Slack format: <@U1234567890>
        match = text.match(/<@(U[A-Z0-9]+)>/)
        match&.[](1)
      when "discord"
        # Discord format: <@123456789012345678> (numeric snowflake IDs)
        match = text.match(/<@!?(\d+)>/)
        match&.[](1)
      end
    end

    # --- Platform-aware thread ID extraction ---

    def thread_id
      case channel.channel_type
      when "slack"
        extract_metadata_value("thread_ts")
      when "discord"
        # Discord threads use channel IDs; thread_id is stored in metadata
        extract_metadata_value("thread_id") || extract_metadata_value("channel_id")
      else
        extract_metadata_value("thread_ts") || extract_metadata_value("thread_id")
      end
    end

    def extract_metadata_value(key)
      if message.is_a?(InboundMessage)
        message.metadata&.dig(key) || message.metadata&.dig(key.to_sym)
      elsif message.respond_to?(:dig)
        message.dig(:metadata, key) || message.dig(:metadata, key.to_sym) ||
          message.dig("metadata", key)
      elsif message.respond_to?(:metadata)
        message.metadata&.dig(key) || message.metadata&.dig(key.to_sym)
      end
    end

    def message_text
      if message.is_a?(InboundMessage)
        message.content
      elsif message.respond_to?(:dig)
        message.dig(:content) || message.dig("content")
      elsif message.respond_to?(:content)
        message.content
      else
        message.to_s
      end
    end

    def check_dm_policy(agent)
      agent_channel = channel.agent_channels.find_by(agent: agent)
      return nil unless agent_channel

      sender = extract_sender
      return nil if sender.blank?

      is_mention = extract_mentioned_bot_id.present?
      result = Channels::DmPolicyChecker.call(
        agent_channel: agent_channel,
        sender: sender,
        is_mention: is_mention
      )

      return nil if result.data[:allowed]

      ServiceResponse.success(data: { agent: agent, blocked: true, reply: result.data[:reply] })
    end

    def extract_sender
      if message.is_a?(InboundMessage)
        message.sender
      elsif message.respond_to?(:dig)
        message.dig(:sender) || message.dig("sender")
      elsif message.respond_to?(:sender)
        message.sender
      end
    end
  end
end
