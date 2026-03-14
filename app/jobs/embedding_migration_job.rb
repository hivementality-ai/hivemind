# frozen_string_literal: true

class EmbeddingMigrationJob < ApplicationJob
  queue_as :low
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  BATCH_SIZE = 100

  # Re-embed existing memory entries using the migration target provider.
  # Processes in batches to avoid memory bloat and rate limits.
  def perform(migration_status_id, offset = 0)
    status = EmbeddingMigrationStatus.find_by(id: migration_status_id)
    return unless status&.active?

    target_provider = status.to_provider
    adapter = Embeddings::Registry.adapter_for(target_provider)

    entries = MemoryEntry
      .where.not(embedding: nil)
      .where(shadow_embedding: nil)
      .order(:id)
      .offset(offset)
      .limit(BATCH_SIZE)

    return if entries.empty?

    target_supports_multimodal = adapter.capabilities[:modalities]&.include?(:image)

    entries.each do |entry|
      next if entry.content.blank?

      shadow = adapter.embed_text(entry.content)
      if shadow
        attrs = { shadow_embedding: shadow }
        # If migrating to a text-only provider, mark multimodal entries as text
        if entry.modality == "multimodal" && !target_supports_multimodal
          Rails.logger.info("[EmbeddingMigrationJob] Entry #{entry.id} degraded from multimodal to text-only")
        end
        entry.update_columns(attrs)
      end
    rescue StandardError => e
      Rails.logger.error("[EmbeddingMigrationJob] Failed to embed entry #{entry.id}: #{e.message}")
    end

    # Enqueue next batch if there are more records without shadow embeddings
    remaining = MemoryEntry
      .where.not(embedding: nil)
      .where(shadow_embedding: nil)
      .count

    if remaining > 0
      self.class.perform_later(migration_status_id, 0)
    else
      Rails.logger.info("[EmbeddingMigrationJob] Batch re-embedding complete for migration #{migration_status_id}")
    end
  end
end
