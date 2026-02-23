# frozen_string_literal: true

class MemoryEmbeddingJob < ApplicationJob
  queue_as :low
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # Generate and persist an embedding for a MemoryEntry
  def perform(memory_entry_id)
    entry = MemoryEntry.find_by(id: memory_entry_id)
    return unless entry
    return if entry.embedded?

    embedding = Memory::Embedding.generate(entry.content)
    return unless embedding

    entry.update!(embedding: embedding)
  rescue ActiveRecord::RecordNotFound
    # Entry was deleted before job ran — no-op
  end
end
