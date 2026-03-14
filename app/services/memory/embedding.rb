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

    # Generate a multimodal embedding (text + media) if the adapter supports it.
    # Falls back to text-only embedding if multimodal is not supported.
    # Accepts any combination of media types:
    #   images:    [{ data: "<base64>", mime_type: "image/png" }]
    #   audio:     [{ data: "<base64>", mime_type: "audio/mp3" }]
    #   video:     [{ data: "<base64>", mime_type: "video/mp4" }]
    #   documents: [{ data: "<base64>", mime_type: "application/pdf" }]
    # Returns { embedding: Array[Float], modality: String } or nil.
    def self.generate_multimodal(text, images: [], audio: [], video: [], documents: [], provider: nil)
      adapter = provider ? Embeddings::Registry.adapter_for(provider) : Embeddings::Registry.current
      return nil unless adapter

      supported = adapter.capabilities[:modalities] || []
      parts = [ { text: text } ]
      has_media = false

      if images.any? && supported.include?(:image)
        parts += images.map { |img| { image: img[:data], mime_type: img[:mime_type] } }
        has_media = true
      end

      if audio.any? && supported.include?(:audio)
        parts += audio.map { |a| { audio: a[:data], mime_type: a[:mime_type] } }
        has_media = true
      end

      if video.any? && supported.include?(:video)
        parts += video.map { |v| { video: v[:data], mime_type: v[:mime_type] } }
        has_media = true
      end

      if documents.any? && supported.include?(:pdf)
        parts += documents.map { |d| { document: d[:data], mime_type: d[:mime_type] } }
        has_media = true
      end

      if has_media
        vector = adapter.embed_multimodal(parts)
        return { embedding: vector, modality: "multimodal" } if vector
      end

      # Fall back to text-only
      vector = adapter.embed_text(text)
      vector ? { embedding: vector, modality: "text" } : nil
    rescue StandardError => e
      Rails.logger.error("[Memory::Embedding] Multimodal embedding failed: #{e.message}")
      nil
    end

    # Check if the current adapter supports multimodal embedding
    def self.multimodal?
      adapter = Embeddings::Registry.current
      return false unless adapter

      capabilities = adapter.capabilities
      (capabilities[:modalities] || []).include?(:image)
    rescue
      false
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
