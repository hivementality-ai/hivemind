# frozen_string_literal: true

class ServiceResponse
  attr_reader :success, :data, :error
  alias_method :success?, :success

  def initialize(success:, data: nil, error: nil)
    @success = success
    @data = data
    @error = error
  end

  def self.success(data: nil)
    new(success: true, data:)
  end

  def self.failure(error:)
    new(success: false, error:)
  end
end
