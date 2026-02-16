# frozen_string_literal: true

require "faraday"

# Signal Connection Manager
# Wraps signal-cli REST API for Signal messaging
class SignalConnection
  SIGNAL_CLI_URL = ENV.fetch("SIGNAL_CLI_URL", "http://signal-cli:8080")

  def initialize(redis:, logger:, callback:)
    @redis = redis
    @logger = logger
    @callback = callback
    @phone_number = ENV["SIGNAL_PHONE_NUMBER"]
    @client = Faraday.new(url: SIGNAL_CLI_URL)
    @state = :disconnected
  end

  def connect
    @logger.info "Signal: Connecting..."

    unless @phone_number
      @logger.error "Signal: SIGNAL_PHONE_NUMBER not set"
      return
    end

    # Check if already registered
    if registered?
      @state = :connected
      start_message_listener
    else
      initiate_registration
    end
  rescue => e
    @logger.error "Signal connect error: #{e.message}"
    @state = :disconnected
  end

  def disconnect
    @logger.info "Signal: Disconnecting..."
    @state = :disconnected
    @listener_thread&.kill
  end

  def reconnect
    disconnect
    sleep 2
    connect
  end

  def send_message(data)
    unless connected?
      @logger.warn "Signal: Cannot send, not connected"
      return
    end

    @logger.info "Signal: Sending to #{data[:to]}"

    payload = {
      number: @phone_number,
      recipients: [ data[:to] ],
      message: data[:text]
    }

    response = @client.post("/v2/send") do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = payload.to_json
    end

    unless response.success?
      @logger.error "Signal send failed: #{response.status} #{response.body}"
    end
  rescue => e
    @logger.error "Signal send error: #{e.message}"
  end

  def connected?
    @state == :connected
  end

  def disconnected?
    @state == :disconnected
  end

  private

  def registered?
    response = @client.get("/v1/accounts/#{@phone_number}")
    response.success?
  rescue
    false
  end

  def initiate_registration
    @logger.info "Signal: Starting registration for #{@phone_number}"

    response = @client.post("/v1/register/#{@phone_number}")

    if response.success?
      @logger.info "Signal: Verification code sent. Check logs or storage for linking."
      store_registration_status("pending_verification")
    else
      @logger.error "Signal registration failed: #{response.body}"
    end
  end

  def store_registration_status(status)
    @redis.setex("connector:signal:registration", 3600, status)
  end

  def start_message_listener
    @logger.info "Signal: Starting message listener..."

    @listener_thread = Thread.new do
      loop do
        poll_messages
        sleep 2
        break if disconnected?
      end
    end
  end

  def poll_messages
    response = @client.get("/v1/receive/#{@phone_number}")
    return unless response.success?

    messages = JSON.parse(response.body, symbolize_names: true)
    messages.each do |msg|
      process_inbound_message(msg)
    end
  rescue => e
    @logger.error "Signal poll error: #{e.message}"
  end

  def process_inbound_message(msg)
    return if msg[:envelope][:dataMessage].nil?

    message_data = {
      from: msg[:envelope][:source],
      text: msg[:envelope][:dataMessage][:message],
      timestamp: msg[:envelope][:timestamp],
      group_id: msg[:envelope][:dataMessage][:groupInfo]&.[](:groupId)
    }

    @callback.call(:signal, message_data)
  rescue => e
    @logger.error "Signal message processing error: #{e.message}"
  end
end
