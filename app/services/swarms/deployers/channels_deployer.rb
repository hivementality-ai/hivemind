# frozen_string_literal: true

module Swarms
  module Deployers
    # Creates or updates Channel records from a SwarmDocument's channels[] section.
    #
    # Each channel entry in the swarm document is a plain Hash (as produced by
    # SwarmParser#normalize_array) with indifferent-access keys.
    #
    # Channels are matched by name. Resolution strategies are keyed by channel name:
    #   :skip      – keep existing channel, return it in the results
    #   :overwrite – update existing channel attributes with swarm values
    #   :rename    – create new channel with an auto-suffixed name
    #   (none)     – create new channel (no conflict expected)
    #
    # The payload always contains a :channels array of DeployResult value objects,
    # one per channel in the document, in document order.
    #
    # Usage:
    #   result = ChannelsDeployer.call(document: swarm_doc, resolutions: {})
    #   result.success?           # => true / false
    #   result.payload[:channels] # => [DeployResult, ...]
    class ChannelsDeployer
      # Outcome for a single deployed channel.
      DeployResult = Data.define(:name, :record, :action) do
        # action is one of: :created, :updated, :skipped, :renamed
      end

      def self.call(document:, resolutions: {})
        new(document, resolutions).call
      end

      def initialize(document, resolutions)
        @document    = document
        @resolutions = resolutions.with_indifferent_access
      end

      def call
        results = @document.channels.map do |channel_hash|
          deploy_channel(channel_hash.with_indifferent_access)
        end

        ServiceResponse.success(payload: { channels: results })
      rescue ActiveRecord::RecordInvalid => e
        ServiceResponse.error(message: "Failed to deploy channels: #{e.record.errors.full_messages.join(', ')}")
      rescue StandardError => e
        ServiceResponse.error(message: "Failed to deploy channels: #{e.message}")
      end

      private

      def deploy_channel(channel_hash)
        name     = channel_hash[:name].to_s
        strategy = @resolutions[name]&.to_sym
        existing = Channel.find_by(name: name)

        if existing.nil?
          record = create_channel(name, channel_hash)
          DeployResult.new(name: name, record: record, action: :created)
        else
          apply_strategy(strategy, existing, name, channel_hash)
        end
      end

      def create_channel(name, channel_hash)
        Channel.create!(build_attributes(name, channel_hash))
      end

      def apply_strategy(strategy, existing, name, channel_hash)
        case strategy
        when :skip
          DeployResult.new(name: name, record: existing, action: :skipped)
        when :overwrite
          existing.update!(build_attributes(name, channel_hash))
          DeployResult.new(name: name, record: existing, action: :updated)
        when :rename
          new_name = unique_name(name)
          record   = create_channel(new_name, channel_hash.merge(name: new_name))
          DeployResult.new(name: new_name, record: record, action: :renamed)
        else
          # No resolution provided but conflict exists — skip to be safe.
          DeployResult.new(name: name, record: existing, action: :skipped)
        end
      end

      def build_attributes(name, channel_hash)
        {
          name:         name,
          channel_type: channel_hash[:type].to_s,
          config:       (channel_hash[:config].presence || {}),
          enabled:      channel_hash.key?(:enabled) ? channel_hash[:enabled] : true
        }
      end

      # Appends an incrementing suffix until the name is unique.
      def unique_name(base)
        candidate = "#{base}-2"
        counter   = 2

        while Channel.exists?(name: candidate)
          counter  += 1
          candidate = "#{base}-#{counter}"
        end

        candidate
      end
    end
  end
end
