# frozen_string_literal: true

module Providers
  # The one place a provider failure becomes a typed verdict.
  #
  # Mirrors sdk-proxy/error-classifier.js so both sides of the proxy agree on
  # what is permanent. When the proxy sends a structured body we trust its
  # verdict verbatim; otherwise (direct API path, Faraday, OpenAI, Ollama) we
  # derive the same answer from status and message here.
  #
  # Deliberate default: anything unclassifiable is PERMANENT. Treating the
  # unknown as retryable is precisely what turned one out-of-credit account
  # into a host-wide ephemeral-port exhaustion on 2026-08-24.
  class ErrorClassifier
    QUOTA_PATTERNS = /
      out\ of\ extra\ usage |
      credit\ balance\ is\ too\ low |
      insufficient[_\s-]?quota |
      billing[_\s-]?(?:hard[_\s-]?)?limit |
      purchase\ (?:more\ )?credits |
      claude\.ai\/settings\/usage
    /xi

    AUTH_PATTERNS = /
      invalid[_\s-]?api[_\s-]?key | authentication[_\s-]?error |
      oauth\ token\ (?:has\ )?expired | invalid\ bearer\ token | unauthorized
    /xi

    MODEL_NOT_FOUND_PATTERNS = /not_found_error | unknown\ model | model[:\s].*not[_\s-]?found/xi

    # Local resource exhaustion. NOT retryable: EADDRNOTAVAIL means the kernel
    # has no ephemeral port left, and every retry makes that worse.
    LOCAL_EXHAUSTION_PATTERNS = /
      EADDRNOTAVAIL | can't\ assign\ requested\ address |
      EMFILE | ENFILE | too\ many\ open\ files
    /xi

    NETWORK_PATTERNS = /
      ECONNRESET | ECONNREFUSED | EPIPE | ENOTFOUND | EAI_AGAIN |
      ETIMEDOUT | ESOCKETTIMEDOUT | socket\ hang\ up | execution\ expired |
      network[_\s-]?error | connection\ (?:error|refused|reset|failed) |
      timed[_\s-]?out | timeout | failed\ to\ open\ tcp
    /xi

    OVERLOAD_PATTERNS = /overloaded | rate[_\s-]?limit | too\ many\ requests/xi

    STATUS_IN_TEXT = /
      \(\s*(\d{3})\s*\) |
      \bAPI\ Error:?\s*(\d{3})\b |
      \bstatus(?:\s*code)?[:\s]+(\d{3})\b |
      \bHTTP\ (\d{3})\b
    /xi

    # reason => [permanent?, default status]
    REASONS = {
      "quota_exhausted"       => [ true,  402 ],
      "auth_invalid"          => [ true,  401 ],
      "forbidden"             => [ true,  403 ],
      "model_not_found"       => [ true,  404 ],
      "invalid_request"       => [ true,  400 ],
      "request_too_large"     => [ true,  413 ],
      "local_port_exhaustion" => [ true,  503 ],
      "unknown"               => [ true,  500 ],
      "rate_limited"          => [ false, 429 ],
      "server_error"          => [ false, 502 ],
      "network_error"         => [ false, 502 ],
      "timeout"               => [ false, 504 ],
      "conflict"              => [ false, 409 ]
    }.freeze

    # Reasons that count toward opening the credential's circuit. A malformed
    # request or a missing model is the caller's bug, not the credential's —
    # those must not silence a working account.
    CIRCUIT_REASONS = %w[quota_exhausted auth_invalid forbidden local_port_exhaustion].freeze

    class << self
      # Build a typed error from anything a provider path can produce.
      #
      # @param message  [String]      the failure text
      # @param status   [Integer,nil] HTTP status if known
      # @param body     [String,Hash,nil] response body; a structured proxy
      #                 body ({"reason":..., "retryable":...}) wins outright
      # @param provider [String,nil]
      # @return [ProviderError]
      def call(message:, status: nil, body: nil, provider: nil)
        verdict = from_structured_body(body) || derive(message.to_s, status, body)

        klass = verdict[:retryable] ? TransientProviderError : PermanentProviderError
        klass.new(
          message.to_s.presence || "Provider call failed (#{verdict[:reason]})",
          status: verdict[:status],
          reason: verdict[:reason],
          provider: provider,
          retry_after: verdict[:retry_after]
        )
      end

      # Classify a ServiceResponse failure string produced by an adapter that
      # has already flattened its error. Used by FailoverAdapter and callers
      # holding only a ServiceResponse.
      def from_error_string(error, provider: nil)
        call(message: error.to_s, status: nil, provider: provider)
      end

      def opens_circuit?(error)
        error.is_a?(ProviderError) && CIRCUIT_REASONS.include?(error.reason)
      end

      def permanent?(reason) = REASONS.fetch(reason.to_s, [ true ]).first

      private

      # The sdk-proxy already classified this; re-deriving from status would
      # be strictly worse (a 503 from an open circuit is not a server error).
      def from_structured_body(body)
        parsed = parse_body(body)
        return nil unless parsed.is_a?(Hash)

        reason = parsed["reason"].presence
        retryable = parsed["retryable"]
        return nil if reason.nil? || ![ true, false ].include?(retryable)

        {
          reason: reason,
          retryable: retryable,
          status: REASONS.dig(reason, 1) || 500,
          retry_after: retry_after_from(parsed)
        }
      end

      def parse_body(body)
        case body
        when Hash then body.stringify_keys
        when String then (JSON.parse(body) if body.strip.start_with?("{"))
        end
      rescue JSON::ParserError
        nil
      end

      def retry_after_from(parsed)
        ms = parsed["retry_after_ms"]
        ms.is_a?(Numeric) ? (ms / 1000.0).ceil : nil
      end

      def derive(message, status, body)
        haystack = [ message, body_text(body) ].compact.join("\n")
        effective_status = status || status_from_text(haystack)
        reason = reason_for_status(effective_status, haystack) || reason_from_text(haystack) || "unknown"

        {
          reason: reason,
          retryable: !permanent?(reason),
          status: effective_status || REASONS.dig(reason, 1) || 500,
          retry_after: nil
        }
      end

      def body_text(body)
        body.is_a?(String) ? body : (body&.to_json if body.respond_to?(:to_json))
      end

      def status_from_text(text)
        match = text.match(STATUS_IN_TEXT)
        return nil unless match

        code = match.captures.compact.first.to_i
        code.between?(400, 599) ? code : nil
      end

      def reason_for_status(status, text)
        case status
        when nil then nil
        when 400 then text.match?(QUOTA_PATTERNS) ? "quota_exhausted" : "invalid_request"
        when 401 then "auth_invalid"
        when 402 then "quota_exhausted"
        when 403 then "forbidden"
        when 404 then "model_not_found"
        when 408 then "timeout"
        when 409 then "conflict"
        when 413 then "request_too_large"
        when 422 then "invalid_request"
        when 429 then "rate_limited"
        when 500..599 then "server_error"
        end
      end

      def reason_from_text(text)
        # Order matters: local exhaustion and quota are checked before the
        # generic network patterns, whose messages often overlap.
        return "local_port_exhaustion" if text.match?(LOCAL_EXHAUSTION_PATTERNS)
        return "quota_exhausted"       if text.match?(QUOTA_PATTERNS)
        return "auth_invalid"          if text.match?(AUTH_PATTERNS)
        return "model_not_found"       if text.match?(MODEL_NOT_FOUND_PATTERNS)
        return "rate_limited"          if text.match?(OVERLOAD_PATTERNS)
        return "network_error"         if text.match?(NETWORK_PATTERNS)

        nil
      end
    end
  end
end
