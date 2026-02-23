# frozen_string_literal: true

module Memory
  class Status
    def self.call
      new.call
    end

    def call
      embedding_available = Memory::Embedding.available?

      {
        embeddings_enabled: embedding_available,
        embedding_provider: embedding_available ? detect_provider : nil,
        total_memories: MemoryEntry.count,
        embedded_memories: MemoryEntry.where.not(embedding: nil).count,
        pending_embeddings: MemoryEntry.where(embedding: nil).count,
        mode: embedding_available ? "semantic" : "keyword"
      }
    end

    private

    def detect_provider
      embedding = Memory::Embedding.new
      # Check Ollama first (preferred), then OpenAI
      if ollama_available?
        "ollama/#{Memory::Embedding::OLLAMA_MODEL}"
      elsif openai_available?
        "openai/#{Memory::Embedding::OPENAI_MODEL}"
      else
        nil
      end
    end

    def ollama_available?
      Memory::Embedding.new(provider: "ollama").available?
    end

    def openai_available?
      Memory::Embedding.new(provider: "openai").available?
    end
  end
end
