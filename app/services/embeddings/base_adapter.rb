# frozen_string_literal: true

module Embeddings
  class BaseAdapter
    def capabilities
      raise NotImplementedError
    end

    # Embed text for storage (document side of asymmetric retrieval)
    def embed_text(text, dimensions: nil)
      raise NotImplementedError
    end

    # Embed text for querying (query side of asymmetric retrieval)
    def embed_query(text, dimensions: nil)
      embed_text(text, dimensions: dimensions, timeouts: recall_timeouts)
    end

    # Health check — is the provider reachable and configured?
    def healthy?
      raise NotImplementedError
    end

    # Estimated cost per 1M tokens (nil for free/local)
    def cost_per_million_tokens
      nil
    end

    protected

    # Short connect/read limits for query-time (recall) calls so an
    # unreachable provider cannot stall a chat turn. Override with
    # MEMORY_RECALL_OPEN_TIMEOUT / MEMORY_RECALL_READ_TIMEOUT (seconds).
    #
    # @return [Hash] Faraday request options
    def recall_timeouts
      {
        open_timeout: ENV.fetch("MEMORY_RECALL_OPEN_TIMEOUT", 1).to_f,
        timeout: ENV.fetch("MEMORY_RECALL_READ_TIMEOUT", 3).to_f
      }
    end

    # POST a JSON body, applying optional Faraday timeout options.
    def post_json(url, body, headers, timeouts: nil)
      Faraday.post(url, body, headers) do |req|
        timeouts&.each { |option, value| req.options.public_send(:"#{option}=", value) }
      end
    end

    def configured_dimensions
      ENV.fetch("MEMORY_EMBEDDING_DIMENSIONS", capabilities[:default_dimensions]).to_i
    end
  end
end
