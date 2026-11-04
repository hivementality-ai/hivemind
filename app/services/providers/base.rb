# frozen_string_literal: true

module Providers
  class Base
    def initialize(config:, api_key: nil)
      @config = config
      @api_key = api_key
    end

    # Send a chat completion request with streaming
    # @param messages [Array<Hash>] Chat messages [{role:, content:}]
    # @param tools [Array<Hash>] Tool definitions
    # @param options [Hash] Model-specific options (temperature, max_tokens, etc.)
    # @yield [chunk] Streamed response chunks
    # @return [ServiceResponse] with data: { content:, usage:, tool_calls: }
    def chat(messages:, tools: [], options: {}, &block)
      raise NotImplementedError, "#{self.class}#chat must be implemented"
    end

    # List available models for this provider
    # @return [ServiceResponse] with data: { models: [...] }
    def models
      raise NotImplementedError, "#{self.class}#models must be implemented"
    end

    # Generate embeddings for text
    # @param text [String] Text to embed
    # @param model [String] Embedding model name
    # @return [ServiceResponse] with data: { embedding: [...] }
    def embed(text:, model: nil)
      raise NotImplementedError, "#{self.class}#embed must be implemented"
    end

    # Provider label used for circuit-breaker keying and error reporting.
    # Subclasses named FooAdapter get "foo" for free.
    def provider_name
      self.class.name.to_s.demodulize.sub(/Adapter\z/, "").underscore
    end

    private

    attr_reader :config, :api_key

    # Wrap one provider call in the per-credential circuit breaker.
    #
    # Failing fast here rather than in the caller is the whole point: an open
    # circuit must not open a socket. On macOS, container egress consumes the
    # host's shared ~16k ephemeral port pool, so an unbounded retry loop in
    # one stack takes down networking for every process on the box.
    #
    # Adapters return ServiceResponse rather than raising, so the failure is
    # inspected here and the typed verdict is attached to the response payload
    # for callers (FailoverAdapter, jobs, the UI) to act on.
    def with_circuit_breaker(credential: api_key, provider: provider_name)
      breaker = CircuitBreaker.new(provider: provider, credential: credential)
      breaker.check!

      result = yield

      if result.is_a?(ServiceResponse) && result.failure?
        error = provider_error_for(result, provider)
        breaker.record_failure(error)
        return with_provider_error(result, error)
      end

      breaker.record_success
      result
    rescue ProviderCircuitOpenError => e
      # Never reached the network. Surface the real reason, not a generic 500.
      Rails.logger.warn("[CircuitBreaker] short-circuited #{provider} call: #{e.reason}")
      with_provider_error(ServiceResponse.failure(error: e.message), e)
    end

    # Prefer a verdict a downstream client already produced (the sdk-proxy
    # sends a structured one) over re-deriving a weaker one from the string.
    def provider_error_for(result, provider)
      existing = result.payload.is_a?(Hash) ? (result.payload[:provider_error] || result.payload["provider_error"]) : nil

      if existing.is_a?(Hash)
        attrs = existing.symbolize_keys
        klass = attrs[:retryable] ? TransientProviderError : PermanentProviderError
        return klass.new(
          attrs[:message].presence || result.error.to_s,
          status: attrs[:status], reason: attrs[:reason], provider: attrs[:provider] || provider
        )
      end

      ErrorClassifier.from_error_string(result.error, provider: provider)
    end

    def with_provider_error(result, error)
      ServiceResponse.failure(
        error: result.error,
        message: result.message,
        payload: (result.payload || {}).merge(provider_error: error.to_h)
      )
    end

    def base_url
      @config.base_url
    end

    def inject_request_payload(result, params)
      if result.success? && result.data[:usage]
        result.data[:usage][:request_payload] = sanitize_payload_for_logging(params)
      end
      result
    end

    def sanitize_payload_for_logging(params)
      payload = params.deep_dup
      if payload[:messages].is_a?(Array)
        payload[:messages] = payload[:messages].map do |msg|
          msg = msg.dup
          if msg[:content].is_a?(String) && msg[:content].length > 2000
            msg[:content] = msg[:content][0..2000] + "... [truncated #{msg[:content].length} chars]"
          elsif msg[:content].is_a?(Array)
            msg[:content] = msg[:content].map do |block|
              block = block.dup
              if block[:text].is_a?(String) && block[:text].length > 2000
                block[:text] = block[:text][0..2000] + "... [truncated #{block[:text].length} chars]"
              end
              block
            end
          end
          msg
        end
      end
      payload.except(:request_options)
    rescue StandardError => e
      { error: "Failed to capture payload: #{e.message}" }
    end
  end
end
