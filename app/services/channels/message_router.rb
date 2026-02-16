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
      return nil unless slack_channel? && bot_mention?

      mentioned_user_id = extract_mentioned_bot_id
      return nil unless mentioned_user_id

      agent_channel = channel.agent_channels
                            .joins(:agent)
                            .where(agents: { enabled: true })
                            .find_by(external_bot_user_id: mentioned_user_id)

      agent_channel&.agent
    end

    def check_thread_ownership
      return nil unless thread_id.present?

      thread_owner = ChannelThread.thread_owner(channel: channel, thread_id: thread_id)

      # Only return if agent is still enabled
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

    # Helper methods for Slack-specific logic
    def slack_channel?
      channel.channel_type == "slack"
    end

    def bot_mention?
      message_text&.match?(/<@U[A-Z0-9]+>/)
    end

    def extract_mentioned_bot_id
      match = message_text&.match(/<@(U[A-Z0-9]+)>/)
      match&.[](1)
    end

    def thread_id
      if message.is_a?(InboundMessage)
        message.metadata&.dig("thread_ts") || message.metadata&.dig(:thread_ts)
      elsif message.respond_to?(:dig)
        message.dig(:metadata, "thread_ts") || message.dig(:metadata, :thread_ts)
      elsif message.respond_to?(:metadata)
        message.metadata&.dig("thread_ts") || message.metadata&.dig(:thread_ts)
      end
    end

    def message_text
      if message.is_a?(InboundMessage)
        message.content
      elsif message.respond_to?(:dig)
        message.dig(:content)
      elsif message.respond_to?(:content)
        message.content
      else
        message.to_s
      end
    end
  end
end
