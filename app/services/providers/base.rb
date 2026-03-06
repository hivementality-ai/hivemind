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

    private

    attr_reader :config, :api_key

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
