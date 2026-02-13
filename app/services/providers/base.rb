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
  end
end
