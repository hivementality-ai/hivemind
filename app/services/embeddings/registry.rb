# frozen_string_literal: true

module Embeddings
  class Registry
    ADAPTERS = {
      "ollama" => "Embeddings::OllamaAdapter",
      "openai" => "Embeddings::OpenaiAdapter",
      "gemini" => "Embeddings::GeminiAdapter"
    }.freeze

    # Returns the active adapter based on configuration
    def self.current
      provider = configured_provider
      return nil unless provider

      adapter_for(provider)
    end

    # Instantiate a specific adapter by provider name
    def self.adapter_for(provider)
      class_name = ADAPTERS[provider]
      raise ArgumentError, "Unknown embedding provider: #{provider}" unless class_name

      class_name.constantize.new
    end

    # List all registered providers with their status
    def self.available
      ADAPTERS.map do |name, class_name|
        adapter = class_name.constantize.new
        {
          name: name,
          capabilities: adapter.capabilities,
          configured: adapter.healthy?,
          cost: adapter.cost_per_million_tokens
        }
      rescue => e
        { name: name, error: e.message, configured: false }
      end
    end

    # Resolve the active provider from config, with auto-detection fallback
    def self.configured_provider
      return nil if ENV["MEMORY_EMBEDDINGS_ENABLED"] == "false"

      # Database setting takes priority (set by setup wizard / embedding migration UI)
      db_provider = Setting.get("memory_embeddings_provider") rescue nil
      return db_provider if db_provider.present? && ADAPTERS.key?(db_provider)

      # Fall back to env var
      env_provider = ENV["MEMORY_EMBEDDINGS_PROVIDER"]
      return env_provider if env_provider.present? && ADAPTERS.key?(env_provider)

      # Check app config
      config_provider = Rails.application.config.try(:memory_embedding_provider)
      return config_provider if config_provider.present? && ADAPTERS.key?(config_provider)

      # Auto-detect: prefer Ollama (free, local), then OpenAI, then Gemini
      auto_detect
    end

    def self.auto_detect
      %w[ollama openai gemini].each do |name|
        adapter = adapter_for(name)
        return name if adapter.healthy?
      rescue
        next
      end
      nil
    end
    private_class_method :auto_detect
  end
end
