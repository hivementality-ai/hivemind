# frozen_string_literal: true

module Memory
  class Status
    def self.call
      new.call
    end

    def call
      provider = Embeddings::Registry.configured_provider
      adapter = provider ? Embeddings::Registry.adapter_for(provider) : nil
      embedding_available = adapter&.healthy? || false

      {
        embeddings_enabled: embedding_available,
        embedding_provider: embedding_available ? provider_label(provider, adapter) : nil,
        available_providers: Embeddings::Registry.available,
        total_memories: MemoryEntry.count,
        embedded_memories: MemoryEntry.where.not(embedding: nil).count,
        pending_embeddings: MemoryEntry.where(embedding: nil).count,
        mode: embedding_available ? "semantic" : "keyword"
      }
    end

    private

    def provider_label(provider, adapter)
      model = case provider
      when "ollama" then ENV.fetch("MEMORY_OLLAMA_MODEL", Embeddings::OllamaAdapter::MODEL)
      when "openai" then ENV.fetch("MEMORY_OPENAI_MODEL", Embeddings::OpenaiAdapter::MODEL)
      when "gemini" then ENV.fetch("MEMORY_GEMINI_MODEL", Embeddings::GeminiAdapter::MODEL)
      else provider
      end
      "#{provider}/#{model}"
    end
  end
end
