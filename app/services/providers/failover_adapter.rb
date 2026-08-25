# frozen_string_literal: true

module Providers
  # Wraps a provider adapter with an ordered failover chain
  # (Agent#fallback_models). When a chat call fails with an
  # unavailability-class error (auth failure, 429, 5xx, timeout, connection
  # error), the same request is retried against the next model in the chain
  # instead of failing the whole agent turn. Content/validation errors fail
  # immediately, and PromptTooLongError propagates untouched so
  # Agents::ToolLoop's auto-compact recovery still works.
  #
  # Built by Providers::Resolver when the agent has fallback_models configured.
  class FailoverAdapter
    # Unavailability-class errors, matched against the adapters' failure
    # strings: "Anthropic API error (429): ...", "the server responded with
    # status 503" (ruby-openai/Faraday), "SDK proxy error (500): ...",
    # Faraday timeout/connection messages, etc. Adapters rescue Faraday
    # errors into ServiceResponse.failure, so string matching here is the
    # one classification point that covers all four adapters.
    RETRYABLE_ERROR = /
      (?:\(|status[:\s])\s*(?:401|403|407|408|429|5\d\d)\b |
      rate[\s_-]?limit | overloaded | too\ many\ requests |
      timed[\s_-]?out | timeout | execution\ expired |
      connection\ (?:refused|reset|failed) | failed\ to\ open\ tcp |
      service\ unavailable | internal\ server\ error |
      unauthorized | forbidden | authentication[\s_-]?error |
      invalid[\s_-]?(?:api[\s_-]?)?key
    /xi

    # Reasons worth trying the next provider for. A credential-scoped failure
    # (out of credit, revoked token, circuit already open) is permanent for
    # *this* credential but the next entry in the chain has its own, so
    # failing over is both correct and bounded by the chain length.
    #
    # Excluded on purpose: invalid_request and request_too_large are the
    # caller's bug and would fail identically on every provider — retrying
    # them across the chain is pure connection churn.
    FAILOVER_REASONS = %w[
      rate_limited server_error network_error timeout conflict
      quota_exhausted auth_invalid forbidden model_not_found
    ].freeze

    # Never fail over on these: the host itself is out of ephemeral ports, so
    # every additional attempt makes the outage worse.
    NEVER_FAILOVER_REASONS = %w[local_port_exhaustion invalid_request request_too_large unknown].freeze

    attr_reader :primary

    # Call sites that type-check the adapter (OAuth/MCP detection) unwrap
    # through this so failover stays transparent to them.
    def self.unwrap(adapter)
      # Module#=== instead of adapter.is_a? — test doubles stub is_a? narrowly.
      self === adapter ? adapter.primary : adapter
    end

    def initialize(primary:, chain:, agent:)
      @primary = primary
      @chain = chain
      @agent = agent
    end

    # ponytail: if a stream fails mid-response the fallback re-streams from
    # the start (possible duplicated tokens). Unavailability errors almost
    # always arrive before the first byte; dedup buffering if it ever matters.
    def chat(messages:, tools: [], options: {}, &block)
      result = @primary.chat(messages:, tools:, options:, &block)
      return result unless retryable_failure?(result)

      original_error = result.error
      @chain.each do |entry|
        adapter = resolve_adapter(entry)
        next unless adapter

        Rails.logger.warn("[Failover] agent=#{@agent&.id} #{original_error.to_s.truncate(200)} -> retrying with #{entry[:provider]}/#{entry[:model]}")
        result = adapter.chat(messages:, tools:, options: options.merge(model: entry[:model]), &block)

        if result&.success?
          record_fallback(entry, original_error)
          result.data[:usage] = (result.data[:usage] || {}).merge(fallback_model: "#{entry[:provider]}/#{entry[:model]}") if result.data.is_a?(Hash)
          return result
        end

        return result unless retryable_failure?(result)
      end

      # Carry the last verdict through so callers still know whether anything
      # about this failure is worth retrying.
      ServiceResponse.failure(
        error: "#{original_error} (#{@chain.size} fallback model(s) also unavailable)",
        payload: result.respond_to?(:payload) && result.payload.is_a?(Hash) ? result.payload : nil
      )
    end

    def models = @primary.models

    def embed(text:, model: nil) = @primary.embed(text:, model:)

    private

    def retryable_failure?(result)
      return false if result.nil? || result.success?

      # Prefer the typed verdict the adapter attached; fall back to the string
      # regex only for adapters that have not been through the classifier.
      reason = result.payload.is_a?(Hash) ? result.payload.dig(:provider_error, :reason) : nil
      return false if reason.present? && NEVER_FAILOVER_REASONS.include?(reason)
      return FAILOVER_REASONS.include?(reason) if reason.present?

      result.error.to_s.match?(RETRYABLE_ERROR)
    end

    def resolve_adapter(entry)
      resolved = Providers::Resolver.call(provider_name: entry[:provider], agent: @agent, failover: false)
      return resolved.data[:adapter] if resolved.success?

      Rails.logger.warn("[Failover] skipping fallback provider #{entry[:provider]}: #{resolved.error}")
      nil
    end

    def record_fallback(entry, original_error)
      AuditLog.record(
        actor_type: "agent",
        actor_id: @agent&.id || "system",
        action: "llm_failover",
        resource: "#{entry[:provider]}/#{entry[:model]}",
        metadata: { error: original_error.to_s.truncate(500) }
      )
    rescue StandardError => e
      Rails.logger.warn("[Failover] audit record failed: #{e.message}")
    end
  end
end
