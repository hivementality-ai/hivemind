# frozen_string_literal: true

class MemoryEmbeddingJob < ApplicationJob
  queue_as :low
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # Generate embedding and check for duplicates
  def perform(memory_entry_id)
    entry = MemoryEntry.find_by(id: memory_entry_id)
    return unless entry
    return if entry.embedded?

    embedding = Memory::Embedding.generate(entry.content)
    return unless embedding

    # Check for near-duplicates before saving
    duplicate = MemoryEntry.find_duplicate(
      embedding: embedding,
      agent: entry.agent,
      threshold: 0.92
    )

    if duplicate && duplicate.id != entry.id
      # Merge into existing: keep the newer content, higher importance
      attrs = {
        content: entry.content,
        metadata: duplicate.metadata.merge(entry.metadata),
        importance: [entry.importance, duplicate.importance].max
      }
      # Dual-write shadow embedding if migration is active
      shadow = Memory::Embedding.generate_shadow(entry.content)
      attrs[:shadow_embedding] = shadow if shadow

      duplicate.update!(attrs)
      entry.destroy!
    else
      attrs = {
        embedding: embedding,
        embedding_provider: Memory::Embedding.provider_name,
        embedding_model: current_model_name
      }
      # Dual-write shadow embedding if migration is active
      shadow = Memory::Embedding.generate_shadow(entry.content)
      attrs[:shadow_embedding] = shadow if shadow

      entry.update!(attrs)
    end
  rescue ActiveRecord::RecordNotFound
    # Entry was deleted before job ran — no-op
  end

  private

  def current_model_name
    adapter = Embeddings::Registry.current
    adapter&.capabilities&.dig(:model) || adapter&.capabilities&.dig(:name)
  end
end
