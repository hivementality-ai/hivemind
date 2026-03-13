# frozen_string_literal: true

module Memory
  class Embedding
    DIMENSIONS = 768

    # Generate an embedding vector for the given text.
    # Returns Array[Float] (768 dims) or nil on failure.
    # Delegates to the pluggable adapter registry.
    def self.generate(text, provider: nil)
      return nil if text.blank?

      adapter = if provider
                  Embeddings::Registry.adapter_for(provider)
      else
                  Embeddings::Registry.current
      end
      return nil unless adapter

      adapter.embed_text(text)
    rescue StandardError => e
      Rails.logger.error("[Memory::Embedding] Failed to generate embedding: #{e.message}")
      nil
    end

    # Generate a query embedding (may use asymmetric task type for providers that support it)
    def self.generate_query(text, provider: nil)
      return nil if text.blank?

      adapter = if provider
                  Embeddings::Registry.adapter_for(provider)
      else
                  Embeddings::Registry.current
      end
      return nil unless adapter

      adapter.embed_query(text)
    rescue StandardError => e
      Rails.logger.error("[Memory::Embedding] Failed to generate query embedding: #{e.message}")
      nil
    end

    # Check if embedding generation is available
    def self.available?
      Embeddings::Registry.current&.healthy? || false
    end

    # Return the active provider name
    def self.provider_name
      Embeddings::Registry.configured_provider
    end

    # Generate a shadow embedding using the migration target provider.
    # Returns nil if no migration is active.
    def self.generate_shadow(text)
      return nil unless migration_active?
      return nil if text.blank?

      target = Setting.get("embedding_migration_target")
      return nil unless target

      adapter = Embeddings::Registry.adapter_for(target)
      adapter.embed_text(text)
    rescue StandardError => e
      Rails.logger.error("[Memory::Embedding] Shadow embedding failed: #{e.message}")
      nil
    end

    def self.migration_active?
      Setting.get("embedding_migration_active") == "true"
    end

    def self.migration_target
      Setting.get("embedding_migration_target")
    end

    # For backward compatibility with Memory::Status
    def initialize(provider: nil)
      @provider = provider
    end

    def available?
      if @provider
        Embeddings::Registry.adapter_for(@provider).healthy?
      else
        self.class.available?
      end
    rescue
      false
    end
  end
end
