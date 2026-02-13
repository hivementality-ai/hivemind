# frozen_string_literal: true

require "net/http"
require "json"

module Tools
  class MessageExecutor < BaseExecutor
    # Send messages via configured channels (Discord, Slack, Telegram, WhatsApp, Signal)
    def call
      action = input["action"].to_s.strip.presence || "send"

      case action
      when "send"
        send_message
      when "list_channels"
        list_channels
      when "react"
        react_to_message
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Supported: send, list_channels, react")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Message error: #{e.message}")
    end

    private

    def send_message
      channel_name = input["channel"].to_s.strip
      to = input["to"].to_s.strip
      message = input["message"].to_s.strip

      return ServiceResponse.failure(error: "No message provided") if message.empty?

      channel = find_channel(channel_name)
      return ServiceResponse.failure(error: not_configured_error(channel_name)) unless channel

      adapter = Channels::Registry.adapter_for(channel)
      result = adapter.send_message(to: to, content: message)

      if result.success?
        ServiceResponse.success(data: {
          output: "Message sent via #{channel.channel_type}#{to.present? ? " to #{to}" : ""}",
          exit_code: 0
        })
      else
        ServiceResponse.failure(error: "Send failed: #{result.error}")
      end
    end

    def list_channels
      channels = Channel.enabled_channels.order(:name)

      if channels.any?
        output = channels.map do |ch|
          "• #{ch.name} (#{ch.channel_type}) — #{ch.enabled? ? '✅ enabled' : '⏸️ disabled'}"
        end.join("\n")
        ServiceResponse.success(data: { output: "Configured channels:\n#{output}", exit_code: 0 })
      else
        ServiceResponse.success(data: {
          output: "No channels configured. Add channels in Platform → Settings.",
          exit_code: 0
        })
      end
    end

    def react_to_message
      channel_name = input["channel"].to_s.strip
      message_id = input["message_id"].to_s.strip
      emoji = input["emoji"].to_s.strip

      return ServiceResponse.failure(error: "channel, message_id, and emoji required") if [channel_name, message_id, emoji].any?(&:empty?)

      channel = find_channel(channel_name)
      return ServiceResponse.failure(error: not_configured_error(channel_name)) unless channel

      adapter = Channels::Registry.adapter_for(channel)

      if adapter.respond_to?(:react)
        result = adapter.react(message_id: message_id, emoji: emoji)
        if result.success?
          ServiceResponse.success(data: { output: "Reacted with #{emoji}", exit_code: 0 })
        else
          ServiceResponse.failure(error: result.error)
        end
      else
        ServiceResponse.failure(error: "#{channel.channel_type} doesn't support reactions")
      end
    end

    def find_channel(name)
      return Channel.enabled_channels.first if name.empty?
      Channel.enabled_channels.find_by(channel_type: name) ||
        Channel.enabled_channels.find_by(name: name)
    end

    def not_configured_error(name)
      available = Channel.enabled_channels.pluck(:channel_type).join(", ")
      if available.present?
        "Channel '#{name}' not found. Available: #{available}"
      else
        "No channels configured. Add channels in Platform → Settings."
      end
    end
  end
end
