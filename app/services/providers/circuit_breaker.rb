# frozen_string_literal: true

module Providers
  # Per-credential circuit breaker for outbound LLM calls.
  #
  # After N consecutive permanent failures on a credential (out of credit,
  # revoked token, forbidden), stop dialling entirely. While the circuit is
  # open every call fails fast in-process: no DNS, no TCP connect, no
  # ephemeral port consumed. That last part is the point — on macOS, container
  # egress runs through the host's own ~16k-port pool shared by every stack on
  # the box, so an unbounded retry loop in one stack is a host-wide outage.
  #
  # State lives in Redis so all Sidekiq workers and Puma processes in a stack
  # share one verdict; a per-process breaker would let N workers each burn
  # their own threshold. Redis being unavailable fails OPEN (allows the call)
  # so a Redis blip never blocks a working provider.
  class CircuitBreaker
    NAMESPACE = "provider_circuit"

    DEFAULT_THRESHOLD = 3
    DEFAULT_OPEN_SECONDS = 15 * 60

    State = Struct.new(:state, :reason, :failures, :opened_at, :message, :credential, :provider, keyword_init: true) do
      def open? = state == "open"
      def closed? = state == "closed"
      def half_open? = state == "half_open"
    end

    class << self
      # Gate a provider call.
      #
      # @raise [ProviderCircuitOpenError] before any socket is opened
      # @return whatever the block returns
      def guard(provider:, credential:)
        breaker = new(provider: provider, credential: credential)
        breaker.check!
        result = yield
        breaker.record_success
        result
      end

      def threshold
        positive_setting("provider_circuit_threshold", ENV["PROVIDER_CIRCUIT_THRESHOLD"]) || DEFAULT_THRESHOLD
      end

      def open_seconds
        positive_setting("provider_circuit_open_seconds", ENV["PROVIDER_CIRCUIT_OPEN_SECONDS"]) || DEFAULT_OPEN_SECONDS
      end

      # Every circuit currently not serving — drives the UI banner and the
      # health endpoint. Bounded scan; there are only ever a handful of keys.
      def open_circuits
        redis = Redis.current
        redis.scan_each(match: "#{NAMESPACE}:*:state", count: 100).filter_map do |key|
          provider, credential = key.delete_prefix("#{NAMESPACE}:").delete_suffix(":state").split("/", 2)
          next if provider.blank? || credential.blank?

          state = new(provider: provider, credential_key: credential).state
          state unless state.closed?
        end
      rescue StandardError => e
        Rails.logger.warn("[CircuitBreaker] open_circuits failed: #{e.message}")
        []
      end

      # Human fixed one provider's credential — resume immediately rather
      # than waiting out the cooldown. Also pokes the sdk-proxy, which keeps
      # its own in-process breaker for the same credential.
      def reset_provider!(provider)
        redis = Redis.current
        keys = redis.scan_each(match: "#{NAMESPACE}:#{provider}/*", count: 100).to_a
        redis.del(*keys) if keys.any?
        Rails.logger.info("[CircuitBreaker] reset #{keys.size} circuit(s) for provider=#{provider}")
        reset_sdk_proxy! if provider.to_s == "anthropic"
        true
      rescue StandardError => e
        Rails.logger.warn("[CircuitBreaker] reset_provider!(#{provider}) failed: #{e.message}")
        false
      end

      # Human fixed the credential — resume immediately rather than waiting
      # out the cooldown.
      def reset_all!
        redis = Redis.current
        keys = redis.scan_each(match: "#{NAMESPACE}:*", count: 100).to_a
        redis.del(*keys) if keys.any?
        true
      rescue StandardError => e
        Rails.logger.warn("[CircuitBreaker] reset_all! failed: #{e.message}")
        false
      end

      private

      # The proxy keeps its own in-process breaker for the same credential.
      # Enqueued rather than called inline so an unreachable proxy never
      # blocks the request that cleared the Rails-side circuit.
      def reset_sdk_proxy!
        ProviderCircuitResetJob.perform_later("anthropic")
      rescue StandardError => e
        Rails.logger.warn("[CircuitBreaker] sdk-proxy circuit reset enqueue failed: #{e.message}")
      end

      def positive_setting(setting_key, env_value)
        raw = (Setting.get(setting_key).presence rescue nil) || env_value
        value = raw.to_i
        value.positive? ? value : nil
      end
    end

    # @param credential [String, nil] the raw API key/token; hashed, never stored
    # @param credential_key [String, nil] an already-hashed key (internal use)
    def initialize(provider:, credential: nil, credential_key: nil)
      @provider = provider.to_s.presence || "unknown"
      @credential_key = credential_key.presence || fingerprint(credential)
    end

    def check!
      current = state
      return if current.closed? || current.half_open?

      retry_at = current.opened_at ? current.opened_at + self.class.open_seconds : nil
      raise ProviderCircuitOpenError.new(
        "Provider unavailable: #{human_reason(current.reason)}. " \
        "Hivemind has stopped calling #{@provider} on this credential until it is fixed.",
        status: 503,
        reason: current.reason,
        provider: @provider,
        opened_at: current.opened_at,
        retry_at: retry_at
      )
    end

    def state
      raw = redis.hgetall(key)
      return closed_state if raw.blank?

      state = raw["state"].presence || "closed"
      opened_at = raw["opened_at"].present? ? Time.zone.at(raw["opened_at"].to_i) : nil

      # open -> half_open once the cooldown elapses; one probe then decides.
      if state == "open" && opened_at && Time.current >= opened_at + self.class.open_seconds
        state = "half_open"
      end

      State.new(
        state: state, reason: raw["reason"].presence, failures: raw["failures"].to_i,
        opened_at: opened_at, message: raw["message"].presence,
        credential: @credential_key, provider: @provider
      )
    rescue StandardError => e
      Rails.logger.warn("[CircuitBreaker] state read failed, failing open: #{e.message}")
      closed_state
    end

    def record_success
      redis.del(key)
      true
    rescue StandardError => e
      Rails.logger.warn("[CircuitBreaker] record_success failed: #{e.message}")
      false
    end

    # @param error [ProviderError]
    # @return [String] the resulting state
    def record_failure(error)
      current = state

      # A failed half-open probe re-opens immediately, whatever its class:
      # the cooldown just expired and the provider is still not serving.
      return reopen! if current.half_open?

      # Transient failures are the caller's business, not the circuit's.
      return current.state unless ErrorClassifier.opens_circuit?(error)

      failures = redis.hincrby(key, "failures", 1)
      redis.hset(key, "reason", error.reason.to_s, "message", error.message.to_s.truncate(500), "provider", @provider)
      redis.expire(key, self.class.open_seconds * 4)

      return "closed" if failures < self.class.threshold

      open!(error.reason, error.message)
    end

    def reset!
      redis.del(key)
    rescue StandardError
      false
    end

    private

    attr_reader :provider

    def open!(reason, message)
      redis.hset(key, "state", "open", "reason", reason.to_s,
                 "message", message.to_s.truncate(500), "opened_at", Time.current.to_i.to_s,
                 "provider", @provider)
      redis.expire(key, self.class.open_seconds * 4)

      # The single alarm line that would have caught the 40-hour silent outage.
      Rails.logger.error(
        "[ALARM][CircuitBreaker] provider circuit OPEN provider=#{@provider} " \
        "credential=#{@credential_key} reason=#{reason} — no further outbound " \
        "calls will be made on this credential until a human acts. #{message.to_s.truncate(200)}"
      )
      notify_open(reason, message)
      "open"
    rescue StandardError => e
      Rails.logger.warn("[CircuitBreaker] open! failed: #{e.message}")
      "closed"
    end

    def reopen!
      redis.hset(key, "state", "open", "opened_at", Time.current.to_i.to_s)
      "open"
    rescue StandardError
      "open"
    end

    def notify_open(reason, message)
      AuditLog.record(
        actor_type: "system", actor_id: "provider_circuit", action: "provider_circuit_opened",
        resource: "#{@provider}/#{@credential_key}",
        metadata: { reason: reason.to_s, message: message.to_s.truncate(500) }
      )
    rescue StandardError => e
      Rails.logger.warn("[CircuitBreaker] audit record failed: #{e.message}")
    end

    def closed_state
      State.new(state: "closed", failures: 0, credential: @credential_key, provider: @provider)
    end

    def human_reason(reason)
      {
        "quota_exhausted" => "the Claude account is out of usage credit (top up at claude.ai/settings/usage)",
        "auth_invalid" => "the API key or OAuth token is invalid or expired",
        "forbidden" => "this credential is not permitted to use the requested model",
        "local_port_exhaustion" => "the host has run out of ephemeral network ports"
      }.fetch(reason.to_s, reason.to_s.tr("_", " ").presence || "provider unavailable")
    end

    def key = "#{NAMESPACE}:#{@provider}/#{@credential_key}:state"

    def redis = Redis.current

    # Never store or log a credential — only a stable, non-reversible label.
    def fingerprint(credential)
      return "anonymous" if credential.blank?

      Digest::SHA256.hexdigest(credential.to_s)[0, 12]
    end
  end
end
