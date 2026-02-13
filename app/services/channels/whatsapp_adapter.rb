# frozen_string_literal: true

module Channels
  # WhatsApp channel adapter
  # Sends outbound messages via Redis pub/sub to connector
  # Receives inbound messages via webhook from connector
  class WhatsappAdapter
    def initialize(channel:)
      @channel = channel
      @redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
    end
    
    def send_message(to:, text:, **options)
      message_data = {
        to: to,
        type: "text",
        text: text,
        timestamp: Time.now.to_i
      }
      
      publish_to_connector(message_data)
      
      ServiceResponse.success(data: { message_id: generate_message_id })
    rescue => e
      ServiceResponse.failure(error: "Failed to send WhatsApp message: #{e.message}")
    end
    
    def send_media(to:, media_url:, caption: nil, **options)
      message_data = {
        to: to,
        type: "media",
        media_url: media_url,
        caption: caption,
        timestamp: Time.now.to_i
      }
      
      publish_to_connector(message_data)
      
      ServiceResponse.success(data: { message_id: generate_message_id })
    rescue => e
      ServiceResponse.failure(error: "Failed to send WhatsApp media: #{e.message}")
    end
    
    def send_reaction(message_id:, emoji:, **options)
      message_data = {
        type: "reaction",
        message_id: message_id,
        emoji: emoji,
        timestamp: Time.now.to_i
      }
      
      publish_to_connector(message_data)
      
      ServiceResponse.success(data: { sent: true })
    rescue => e
      ServiceResponse.failure(error: "Failed to send WhatsApp reaction: #{e.message}")
    end
    
    def process_inbound(payload)
      # Webhook payload from connector
      message = {
        channel_id: @channel.id,
        external_id: payload["id"],
        from: payload["from"],
        text: payload["text"],
        metadata: {
          timestamp: payload["timestamp"],
          media: payload["media"]
        }
      }
      
      # Create inbound message record
      inbound = InboundMessage.create!(message)
      
      # Route to appropriate agent/session
      route_to_agent(inbound)
      
      ServiceResponse.success(data: { message: inbound })
    rescue => e
      ServiceResponse.failure(error: "Failed to process WhatsApp inbound: #{e.message}")
    end
    
    def connection_status
      # Check connector health via Redis
      qr_code = @redis.get("connector:whatsapp:qr")
      session = @redis.get("connector:whatsapp:session")
      
      if session
        { status: :connected, qr_code: nil }
      elsif qr_code
        { status: :pairing, qr_code: qr_code }
      else
        { status: :disconnected, qr_code: nil }
      end
    rescue => e
      { status: :error, error: e.message }
    end
    
    private
    
    def publish_to_connector(data)
      @redis.publish("connector:outbound:whatsapp", data.to_json)
    end
    
    def generate_message_id
      "wa_#{SecureRandom.hex(16)}"
    end
    
    def route_to_agent(inbound_message)
      # Find or create session for this sender
      # Route to default agent or lookup by channel routing rules
      # This would integrate with existing session/agent routing logic
      
      # Placeholder - actual implementation would use existing routing service
      Rails.logger.info "Routing WhatsApp message from #{inbound_message.from}"
    end
  end
end
