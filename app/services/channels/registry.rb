# frozen_string_literal: true

module Channels
  class Registry
    BUILTIN_ADAPTERS = {
      "discord" => "Channels::DiscordAdapter",
      "slack" => "Channels::SlackAdapter",
      "telegram" => "Channels::TelegramAdapter",
      "whatsapp" => "Channels::WhatsappAdapter",
      "signal" => "Channels::SignalAdapter"
    }.freeze

    # Backwards compatibility alias
    ADAPTERS = BUILTIN_ADAPTERS

    class << self
      def adapter_for(channel)
        klass_name = all_adapters[channel.channel_type]
        raise "Unknown channel type: #{channel.channel_type}" unless klass_name

        klass_name.constantize.new(channel)
      end

      def register(type, class_name)
        plugin_adapters[type.to_s] = class_name.to_s
      end

      def unregister(type)
        plugin_adapters.delete(type.to_s)
      end

      def all_adapters
        BUILTIN_ADAPTERS.merge(plugin_adapters)
      end

      def supported_types
        all_adapters.keys
      end

      def registered?(type)
        all_adapters.key?(type.to_s)
      end

      def builtin?(type)
        BUILTIN_ADAPTERS.key?(type.to_s)
      end

      def plugin_registered?(type)
        plugin_adapters.key?(type.to_s)
      end

      def reset_plugin_adapters!
        @plugin_adapters = {}
      end

      private

      def plugin_adapters
        @plugin_adapters ||= {}
      end
    end
  end
end
