# frozen_string_literal: true

# Base class for LLM provider failures that carry a machine-readable verdict.
#
# The distinction that matters is not "what went wrong" but "will dialling
# again ever help". Callers must be able to answer that without matching on
# error strings — see Providers::ErrorClassifier, which is the one place a
# provider failure becomes one of these.
class ProviderError < StandardError
  attr_reader :status, :reason, :provider, :retry_after

  def initialize(message = nil, status: nil, reason: nil, provider: nil, retry_after: nil)
    super(message)
    @status = status
    @reason = reason
    @provider = provider
    @retry_after = retry_after
  end

  def retryable? = raise(NotImplementedError)

  def to_h
    { message: message, status: status, reason: reason, provider: provider, retryable: retryable? }
  end
end
