# frozen_string_literal: true

module Embeddings
  class Migration
    class Error < StandardError; end

    # Start shadow-writing phase: new memories get dual-written
    # and kick off batch re-embedding of existing records.
    def self.start_shadow_phase!(from_provider:, to_provider:)
      raise Error, "Migration already active" if active_migration.present?
      raise Error, "Unknown target provider: #{to_provider}" unless Registry::ADAPTERS.key?(to_provider)
      raise Error, "Target provider not healthy" unless Registry.adapter_for(to_provider).healthy?

      # Check for multimodal degradation
      from_adapter = Registry.adapter_for(from_provider)
      to_adapter = Registry.adapter_for(to_provider)
      from_modalities = from_adapter.capabilities[:modalities] || []
      to_modalities = to_adapter.capabilities[:modalities] || []
      losing_multimodal = from_modalities.include?(:image) && !to_modalities.include?(:image)

      status = EmbeddingMigrationStatus.create!(
        from_provider: from_provider,
        to_provider: to_provider,
        phase: "shadow",
        started_at: Time.current,
        validation_results: { multimodal_degradation: losing_multimodal }
      )

      # Enable dual-write via settings
      Setting.set("embedding_migration_active", "true")
      Setting.set("embedding_migration_target", to_provider)

      # Enqueue batch re-embedding of existing records
      EmbeddingMigrationJob.perform_later(status.id)

      status
    end

    # Validate migration: compare search quality between old and new embeddings
    def self.validate!(migration_id = nil)
      status = migration_id ? EmbeddingMigrationStatus.find(migration_id) : active_migration
      raise Error, "No active migration found" unless status
      raise Error, "Migration not in shadow phase" unless status.phase == "shadow"

      results = Embeddings::ValidationService.new(status).validate
      status.update!(
        phase: "validated",
        validated_at: Time.current,
        validation_results: results
      )

      status
    end

    # Cutover: swap shadow_embedding → embedding atomically
    def self.cutover!(migration_id = nil)
      status = migration_id ? EmbeddingMigrationStatus.find(migration_id) : active_migration
      raise Error, "No active migration found" unless status
      raise Error, "Migration must be validated before cutover" unless status.phase == "validated"

      ActiveRecord::Base.transaction do
        # Swap columns atomically
        conn = ActiveRecord::Base.connection
        conn.execute("ALTER TABLE memory_entries RENAME COLUMN embedding TO old_embedding")
        conn.execute("ALTER TABLE memory_entries RENAME COLUMN shadow_embedding TO embedding")
        conn.execute("ALTER TABLE memory_entries RENAME COLUMN old_embedding TO shadow_embedding")

        # Update provider tracking on all entries that had shadow embeddings
        MemoryEntry.where.not(embedding: nil).update_all(
          embedding_provider: status.to_provider
        )

        # Clear shadow column (now holds old embeddings)
        MemoryEntry.update_all(shadow_embedding: nil)

        # Update migration status
        status.update!(
          phase: "complete",
          completed_at: Time.current
        )

        # Disable dual-write
        Setting.set("embedding_migration_active", "false")
        Setting.set("embedding_migration_target", "")
      end

      status
    end

    # Rollback: swap columns back and restore old embeddings
    def self.rollback!(migration_id = nil)
      status = migration_id ? EmbeddingMigrationStatus.find(migration_id) : active_migration
      raise Error, "No active migration found" unless status
      raise Error, "Cannot rollback a completed migration (shadow data already cleared)" if status.phase == "complete"

      ActiveRecord::Base.transaction do
        # Clear shadow embeddings
        MemoryEntry.update_all(shadow_embedding: nil)

        # Update migration status
        status.update!(
          phase: "rolled_back",
          rolled_back_at: Time.current
        )

        # Disable dual-write
        Setting.set("embedding_migration_active", "false")
        Setting.set("embedding_migration_target", "")
      end

      status
    end

    # Return progress info for the active migration
    def self.progress
      status = active_migration
      return nil unless status

      total = MemoryEntry.where.not(embedding: nil).count
      shadow_done = MemoryEntry.where.not(shadow_embedding: nil).count

      multimodal_count = MemoryEntry.multimodal.count

      {
        id: status.id,
        from_provider: status.from_provider,
        to_provider: status.to_provider,
        phase: status.phase,
        total_entries: total,
        shadow_entries: shadow_done,
        multimodal_entries: multimodal_count,
        percent_complete: total > 0 ? ((shadow_done.to_f / total) * 100).round(1) : 0,
        started_at: status.started_at,
        validated_at: status.validated_at,
        validation_results: status.validation_results
      }
    end

    def self.active_migration
      EmbeddingMigrationStatus.active.order(created_at: :desc).first
    end
  end
end
