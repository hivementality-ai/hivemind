# frozen_string_literal: true

module Channels
  class OriginDelivery
    # Delivers agent responses back to the originating channel (e.g., WhatsApp).
    # Called after ChatStreamJob completes or when background tasks finish.
    #
    # Only delivers to WhatsApp origins. Slack is excluded by design.

    SUPPORTED_ORIGINS = %w[whatsapp].freeze

    def self.call(session:, content:, agent: nil)
      new(session:, content:, agent:).call
    end

    def initialize(session:, content:, agent: nil)
      @session = session
      @content = content
      @agent = agent || session.agent
    end

    def call
      return unless should_deliver?
      return if @content.blank?

      channel = Channel.find_by(id: @session.origin_channel_id)
      return unless channel&.enabled?

      adapter = Channels::Registry.adapter_for(channel)
      adapter.send_message(to: @session.origin_sender, content: @content)

      Rails.logger.info("[OriginDelivery] Sent to #{@session.origin_channel_type} (#{@session.origin_sender})")
    rescue StandardError => e
      Rails.logger.error("[OriginDelivery] Failed: #{e.message}")
    end

    private

    def should_deliver?
      @session.origin_channel_type.present? &&
        SUPPORTED_ORIGINS.include?(@session.origin_channel_type) &&
        @session.origin_sender.present? &&
        @session.origin_channel_id.present?
    end
  end
end
