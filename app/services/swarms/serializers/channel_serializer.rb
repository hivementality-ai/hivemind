# frozen_string_literal: true

module Swarms
  module Serializers
    # Converts a Channel record into a swarm channels[] entry hash.
    #
    # The swarm format requires ref (a URL-safe identifier derived from name),
    # name, and type. Connection config is included when present, with sensitive
    # values expected to be stripped downstream by SecretStripper.
    #
    # Usage:
    #   hash = ChannelSerializer.call(channel: channel_record)
    #   # => { "ref" => "my-channel", "name" => "My Channel", "type" => "slack", ... }
    class ChannelSerializer
      def self.call(channel:)
        new(channel).call
      end

      def initialize(channel)
        @channel = channel
      end

      def call
        hash = {
          "ref"  => @channel.name.parameterize,
          "name" => @channel.name,
          "type" => @channel.channel_type
        }

        hash["config"]  = @channel.config  if @channel.config.present?
        hash["enabled"] = @channel.enabled unless @channel.enabled.nil?

        hash
      end
    end
  end
end
