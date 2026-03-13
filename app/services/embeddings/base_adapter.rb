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
      embed_text(text, dimensions: dimensions)
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

    def configured_dimensions
      ENV.fetch("MEMORY_EMBEDDING_DIMENSIONS", capabilities[:default_dimensions]).to_i
    end
  end
end
