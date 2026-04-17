# frozen_string_literal: true

class ServiceResponse
  attr_reader :success, :data, :error, :message, :payload
  alias_method :success?, :success

  def initialize(success:, data: nil, error: nil, message: nil, payload: nil)
    @success = success
    @data    = data
    @error   = error
    @message = message
    @payload = payload
  end

  def self.success(data: nil, payload: nil)
    new(success: true, data:, payload:)
  end

  def self.failure(error:, message: nil, payload: nil)
    new(success: false, error:, message: message || error, payload:)
  end

  # Convenience constructor used by swarm services and anywhere a descriptive
  # message is more natural than an error object.
  def self.error(message:, payload: nil)
    new(success: false, error: message, message:, payload:)
  end

  def error?
    !success?
  end
end
