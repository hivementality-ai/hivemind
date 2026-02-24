# frozen_string_literal: true

# Redis-backed signal store for interrupting active agent sessions.
# Signals are checked at natural pause points (before LLM calls, between tool executions).
class SessionSignal
  NAMESPACE = "session_signal"
  TTL = 60 # seconds — safety net, signals shouldn't linger

  TYPES = %w[cancel redirect inject].freeze

  # Set a signal for a session
  # @param session_id [Integer]
  # @param type [String] "cancel", "redirect", or "inject"
  # @param message [String, nil] required for redirect and inject
  def self.set(session_id, type:, message: nil)
    raise ArgumentError, "Unknown signal type: #{type}" unless TYPES.include?(type.to_s)
    raise ArgumentError, "Message required for #{type}" if type.to_s != "cancel" && message.blank?

    data = { type: type.to_s, message: message, timestamp: Time.current.iso8601 }.to_json
    Redis.current.setex("#{NAMESPACE}:#{session_id}", TTL, data)
  end

  # Check for a signal and consume it (atomic read + delete)
  # @param session_id [Integer]
  # @return [Hash, nil] { type:, message:, timestamp: } or nil
  def self.check(session_id)
    key = "#{NAMESPACE}:#{session_id}"
    data = Redis.current.getdel(key)
    return nil unless data

    JSON.parse(data, symbolize_names: true)
  rescue JSON::ParserError
    nil
  end

  # Peek at a signal without consuming it
  # @param session_id [Integer]
  # @return [Hash, nil]
  def self.peek(session_id)
    data = Redis.current.get("#{NAMESPACE}:#{session_id}")
    return nil unless data

    JSON.parse(data, symbolize_names: true)
  rescue JSON::ParserError
    nil
  end

  # Clear any pending signal
  def self.clear(session_id)
    Redis.current.del("#{NAMESPACE}:#{session_id}")
  end

  # Convenience methods
  def self.cancel(session_id)
    set(session_id, type: "cancel")
  end

  def self.redirect(session_id, message:)
    set(session_id, type: "redirect", message: message)
  end

  def self.inject(session_id, message:)
    set(session_id, type: "inject", message: message)
  end
end
