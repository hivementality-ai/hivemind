# frozen_string_literal: true

# A provider failure that cannot succeed on retry until a human acts:
# exhausted credit, a revoked token, a model that does not exist, a malformed
# request. Retrying these opens a fresh TCP connection per attempt against a
# host-wide, finite ephemeral port pool and can never succeed.
#
# Jobs `discard_on` this. Never `retry_on` it.
class PermanentProviderError < ProviderError
  def retryable? = false
end
