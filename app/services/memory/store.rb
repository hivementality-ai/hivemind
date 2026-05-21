# frozen_string_literal: true

module Memory
  class Store
    def self.call(agent:, content:, source: nil, metadata: {}, memory_type: "episodic",
                  importance: 0.5, category: "general", async: true)
      new(
        agent:, content:, source:, metadata:, memory_type:,
        importance:, category:, async:
      ).call
    end

    def initialize(agent:, content:, source: nil, metadata: {}, memory_type: "episodic",
                   importance: 0.5, category: "general", async: true)
      @agent       = agent
      @content     = content
      @source      = source
      @metadata    = metadata
      @memory_type = memory_type
      @importance  = importance
      @category    = category
      @async       = async
    end

    def call
      return ServiceResponse.failure(error: "Content cannot be blank") if @content.blank?

      if @async
        # Create entry, enqueue embedding + dedup check
        memory_entry = create_entry(embedding: nil)
        MemoryEmbeddingJob.perform_later(memory_entry.id) if memory_entry.persisted?
      else
        embedding = Memory::Embedding.generate(@content)

        # Check for duplicates if we have an embedding
        if embedding
          existing = MemoryEntry.find_duplicate(embedding: embedding, agent: @agent)
          if existing
            # Merge: update the existing entry with fresher content
            existing.update!(
              content: @content,
              metadata: existing.metadata.merge(@metadata),
              importance: [ @importance, existing.importance ].max
            )
            return ServiceResponse.success(data: { memory_entry: existing, merged: true })
          end
        end

        memory_entry = create_entry(embedding: embedding)
      end

      if memory_entry.persisted?
        ServiceResponse.success(data: { memory_entry:, merged: false })
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
        metadata: @metadata,
        memory_type: @memory_type,
        importance: @importance,
        category: @category
      )
    end
  end
end
