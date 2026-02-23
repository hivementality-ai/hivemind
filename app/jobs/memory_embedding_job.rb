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
      duplicate.update!(
        content: entry.content,
        metadata: duplicate.metadata.merge(entry.metadata),
        importance: [entry.importance, duplicate.importance].max
      )
      entry.destroy!
    else
      entry.update!(embedding: embedding)
    end
  rescue ActiveRecord::RecordNotFound
    # Entry was deleted before job ran — no-op
  end
end
