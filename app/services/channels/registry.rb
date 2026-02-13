# frozen_string_literal: true

module Channels
  class Registry
    ADAPTERS = {
      "discord" => "Channels::DiscordAdapter",
      "slack" => "Channels::SlackAdapter",
      "telegram" => "Channels::TelegramAdapter",
      "whatsapp" => "Channels::WhatsappAdapter",
      "signal" => "Channels::SignalAdapter"
    }.freeze

    def self.adapter_for(channel)
      klass_name = ADAPTERS[channel.channel_type]
      raise "Unknown channel type: #{channel.channel_type}" unless klass_name

      klass_name.constantize.new(channel)
    end

    def self.supported_types
      ADAPTERS.keys
    end
  end
end
