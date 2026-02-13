# frozen_string_literal: true

module Channels
  # Signal channel adapter
  # Sends outbound messages via Redis pub/sub to connector
  # Receives inbound messages via webhook from connector
  class SignalAdapter
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
      ServiceResponse.failure(error: "Failed to send Signal message: #{e.message}")
    end
    
    def process_inbound(payload)
      # Webhook payload from connector
      message = {
        channel_id: @channel.id,
        external_id: payload["timestamp"],
        from: payload["from"],
        text: payload["text"],
        metadata: {
          group_id: payload["group_id"]
        }
      }
      
      # Create inbound message record
      inbound = InboundMessage.create!(message)
      
      # Route to appropriate agent/session
      route_to_agent(inbound)
      
      ServiceResponse.success(data: { message: inbound })
    rescue => e
      ServiceResponse.failure(error: "Failed to process Signal inbound: #{e.message}")
    end
    
    def connection_status
      # Check connector health via Redis
      registration = @redis.get("connector:signal:registration")
      
      case registration
      when "pending_verification"
        { status: :pending_verification }
      when nil
        { status: :disconnected }
      else
        { status: :connected }
      end
    rescue => e
      { status: :error, error: e.message }
    end
    
    private
    
    def publish_to_connector(data)
      @redis.publish("connector:outbound:signal", data.to_json)
    end
    
    def generate_message_id
      "signal_#{SecureRandom.hex(16)}"
    end
    
    def route_to_agent(inbound_message)
      # Find or create session for this sender
      # Route to default agent or lookup by channel routing rules
      
      # Placeholder - actual implementation would use existing routing service
      Rails.logger.info "Routing Signal message from #{inbound_message.from}"
    end
  end
end
