# frozen_string_literal: true

module Memory
  class Store
    def self.call(agent:, content:, source: nil, metadata: {}, async: true)
      new(agent:, content:, source:, metadata:, async:).call
    end

    def initialize(agent:, content:, source: nil, metadata: {}, async: true)
      @agent = agent
      @content = content
      @source = source
      @metadata = metadata
      @async = async
    end

    def call
      return ServiceResponse.failure(error: "Content cannot be blank") if @content.blank?

      # Create the entry first (without embedding if async)
      if @async
        memory_entry = create_entry(embedding: nil)
        MemoryEmbeddingJob.perform_later(memory_entry.id) if memory_entry.persisted?
      else
        embedding = Memory::Embedding.generate(@content)
        memory_entry = create_entry(embedding: embedding)
      end

      if memory_entry.persisted?
        ServiceResponse.success(data: { memory_entry: })
      else
        ServiceResponse.failure(error: memory_entry.errors.full_messages)
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Memory storage failed: #{e.message}")
    end

    private

    def create_entry(embedding:)
      MemoryEntry.create(
        agent: @agent,
        content: @content,
        embedding: embedding,
        source: @source,
        metadata: @metadata
      )
    end
  end
end
