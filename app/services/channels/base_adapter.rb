# frozen_string_literal: true

module Channels
  class BaseAdapter
    attr_reader :channel

    def initialize(channel)
      @channel = channel
    end

    # Handle incoming message
    # @param message [Hash] Raw message data from the channel
    # @return [ServiceResponse]
    def receive(message)
      raise NotImplementedError, "#{self.class} must implement #receive"
    end

    # Send outbound message
    # @param to [String] Recipient identifier (chat_id, user_id, etc.)
    # @param content [String] Message content
    # @param options [Hash] Additional options (attachments, formatting, etc.)
    # @return [ServiceResponse]
    def send_message(to:, content:, **options)
      raise NotImplementedError, "#{self.class} must implement #send_message"
    end

    # Verify webhook authenticity
    # @param request [ActionDispatch::Request] The HTTP request
    # @return [Boolean]
    def verify_webhook(request)
      raise NotImplementedError, "#{self.class} must implement #verify_webhook"
    end

    # Edit a previously sent message
    # @param message_id [String] Platform message identifier
    # @param content [String] New content for the message
    # @return [ServiceResponse]
    def edit_message(message_id, content, **options)
      raise NotImplementedError, "Message editing is not supported on this channel"
    end

    # Delete a previously sent message
    # @param message_id [String] Platform message identifier
    # @return [ServiceResponse]
    def delete_message(message_id, **options)
      raise NotImplementedError, "Message deletion is not supported on this channel"
    end

    protected

    # Get webhook secret from vault
    def webhook_secret
      @webhook_secret ||= begin
        vault_entry = VaultEntry.find_by(
          namespace: "channel_webhooks",
          key: "#{channel.channel_type}_secret"
        )
        vault_entry&.encrypted_value
      end
    end

    # Verify HMAC signature
    def verify_hmac_signature(payload:, signature:, algorithm: "sha256")
      return false unless webhook_secret

      expected = OpenSSL::HMAC.hexdigest(algorithm, webhook_secret, payload)
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end

    # Log inbound message
    def log_inbound_message(external_id:, sender:, content:, metadata: {}, file_ids: [])
      InboundMessage.create!(
        channel_id: channel.id,
        external_id: external_id,
        sender: sender,
        content: content,
        metadata: metadata,
        received_at: Time.current
      )
    end

    # Log outbound message
    def log_outbound_message(recipient:, content:, metadata: {}, platform_message_id: nil)
      OutboundMessage.create!(
        channel_id: channel.id,
        recipient: recipient,
        content: content,
        metadata: metadata,
        platform_message_id: platform_message_id,
        sent_at: Time.current
      )
    end

    # Transcribe an inbound voice note / audio file to text via the STT tool.
    # Shared hook so every channel that receives audio gets the same behaviour.
    # Returns the transcription string, or nil if the file is missing/unsupported
    # or transcription fails (caller should fall back to any text body).
    def transcribe_audio(file_path)
      return nil if file_path.blank?
      return nil unless File.exist?(file_path.to_s)

      result = Tools::SttExecutor.new(
        input: { "file_path" => file_path.to_s },
        config: {},
        agent: nil
      ).call

      result.success? ? result.data[:transcription] : nil
    rescue StandardError => e
      Rails.logger.warn("[#{channel&.channel_type}] voice transcription failed: #{e.message}")
      nil
    end
  end
end
