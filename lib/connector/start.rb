#!/usr/bin/env ruby
# frozen_string_literal: true

require "redis"
require "faraday"
require "json"
require "logger"

require_relative "whatsapp_connection"
require_relative "signal_connection"

# Connector Sidecar - Maintains persistent channel connections
# Forwards inbound messages to Rails via HTTP POST
# Listens for outbound message requests on Redis pub/sub
class ConnectorDaemon
  REDIS_URL = ENV.fetch("REDIS_URL", "redis://redis:6379/0")
  RAILS_URL = ENV.fetch("RAILS_INTERNAL_URL", "http://rails:3000")
  
  def initialize
    @logger = Logger.new($stdout)
    @logger.level = Logger::INFO
    @redis = Redis.new(url: REDIS_URL)
    @http = Faraday.new(url: RAILS_URL)
    @connections = {}
    @running = true
    
    setup_signal_handlers
  end
  
  def start
    @logger.info "🐝 Connector starting..."
    @logger.info "Redis: #{REDIS_URL}"
    @logger.info "Rails: #{RAILS_URL}"
    
    # Initialize connections
    initialize_connections
    
    # Start listening for outbound messages
    Thread.new { listen_for_outbound }
    
    # Keep main thread alive
    while @running
      sleep 1
      health_check
    end
    
    shutdown
  end
  
  private
  
  def initialize_connections
    @logger.info "Initializing channel connections..."
    
    # WhatsApp connection
    if ENV["WHATSAPP_ENABLED"] == "true"
      @connections[:whatsapp] = WhatsAppConnection.new(
        redis: @redis,
        logger: @logger,
        callback: method(:forward_inbound)
      )
      @connections[:whatsapp].connect
    end
    
    # Signal connection
    if ENV["SIGNAL_ENABLED"] == "true"
      @connections[:signal] = SignalConnection.new(
        redis: @redis,
        logger: @logger,
        callback: method(:forward_inbound)
      )
      @connections[:signal].connect
    end
  end
  
  def listen_for_outbound
    @logger.info "Listening for outbound messages on Redis..."
    
    @redis.subscribe("connector:outbound:whatsapp", "connector:outbound:signal") do |on|
      on.message do |channel, message|
        handle_outbound(channel, message)
      end
    end
  rescue => e
    @logger.error "Error in outbound listener: #{e.message}"
    @logger.error e.backtrace.join("\n")
    sleep 5
    retry if @running
  end
  
  def handle_outbound(channel, message)
    data = JSON.parse(message, symbolize_names: true)
    channel_type = channel.split(":").last.to_sym
    
    @logger.info "Outbound message for #{channel_type}: #{data[:to]}"
    
    connection = @connections[channel_type]
    if connection
      connection.send_message(data)
    else
      @logger.warn "No connection for #{channel_type}"
    end
  rescue => e
    @logger.error "Error handling outbound: #{e.message}"
  end
  
  def forward_inbound(channel_type, message_data)
    @logger.info "Forwarding inbound #{channel_type} message to Rails"
    
    response = @http.post("/webhooks/#{channel_type}") do |req|
      req.headers["Content-Type"] = "application/json"
      req.headers["X-Connector-Secret"] = ENV["CONNECTOR_SECRET"]
      req.body = message_data.to_json
    end
    
    unless response.success?
      @logger.warn "Rails webhook returned #{response.status}: #{response.body}"
    end
  rescue => e
    @logger.error "Error forwarding to Rails: #{e.message}"
  end
  
  def health_check
    # Reconnect any disconnected channels
    @connections.each do |type, conn|
      if conn.disconnected?
        @logger.warn "#{type} disconnected, attempting reconnect..."
        conn.reconnect
      end
    end
  end
  
  def setup_signal_handlers
    %w[INT TERM].each do |signal|
      Signal.trap(signal) do
        @logger.info "Received #{signal}, shutting down gracefully..."
        @running = false
      end
    end
  end
  
  def shutdown
    @logger.info "Shutting down connections..."
    @connections.each_value(&:disconnect)
    @redis.close
    @logger.info "Connector stopped."
  end
end

# Start the daemon
ConnectorDaemon.new.start if __FILE__ == $PROGRAM_NAME
