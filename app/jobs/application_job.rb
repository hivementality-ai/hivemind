# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # ── Retry policy ──────────────────────────────────────────────────────
  #
  # Every job in this app inherits an explicit, bounded policy. Without one,
  # a raised error falls through to Sidekiq's default of 25 retries — and for
  # anything that reaches an LLM provider, each of those attempts opens fresh
  # TCP connections against the host's shared ephemeral port pool. On
  # 2026-08-24 a permanently-failing provider call retried that way for 40
  # hours and exhausted every port on the machine, killing outbound
  # networking for unrelated software on the same host.
  #
  # ActiveSupport::Rescuable matches handlers last-declared-first, so the
  # broad policy is declared FIRST and the specific overrides after it.

  # Broad floor: bounded, backed off, never Sidekiq's 25.
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # Transient provider failures (429, 5xx, timeouts, socket errors) may
  # succeed later. Small cap, exponential backoff.
  retry_on TransientProviderError, wait: :polynomially_longer, attempts: 3

  # Permanent provider failures (out of credit, revoked token, bad request)
  # cannot succeed on retry until a human acts. Retrying them is exactly the
  # behaviour that caused the outage: discard on the first occurrence. The
  # circuit breaker in Providers::CircuitBreaker has already recorded it, and
  # the UI banner surfaces it — nothing is lost by not retrying.
  discard_on PermanentProviderError do |job, error|
    Rails.logger.error(
      "[#{job.class.name}] discarded — permanent provider failure " \
      "(#{error.reason}): #{error.message}"
    )
  end

  # Nothing to act on: the records are gone.
  discard_on ActiveJob::DeserializationError

  # User-driven control flow, not failure. These are handled inside the jobs
  # that raise them; if one escapes, retrying would replay a cancelled turn.
  discard_on AgentInterrupted
end
