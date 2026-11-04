# frozen_string_literal: true

# Raised instead of dialling when a credential's circuit is open. Its whole
# purpose is that no socket is opened, so it must never be retried: the
# circuit itself decides when to probe again.
class ProviderCircuitOpenError < PermanentProviderError
  attr_reader :opened_at, :retry_at

  def initialize(message = nil, opened_at: nil, retry_at: nil, **kwargs)
    super(message, **kwargs)
    @opened_at = opened_at
    @retry_at = retry_at
  end
end
