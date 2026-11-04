# frozen_string_literal: true

# A provider failure that may succeed later: 429, 5xx, timeouts, socket
# errors. Safe to retry, but only with backoff and a small attempt cap —
# see ApplicationJob.
class TransientProviderError < ProviderError
  def retryable? = true
end
