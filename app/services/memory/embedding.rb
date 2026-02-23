# frozen_string_literal: true

module Memory
  class Embedding
    OLLAMA_MODEL = "nomic-embed-text"
    OPENAI_MODEL = "text-embedding-3-small"
    DIMENSIONS = 768

    # Generate an embedding vector for the given text.
    # Returns Array[Float] (768 dims) or nil on failure.
    def self.generate(text, provider: nil)
      new(provider: provider).generate(text)
    end

    # Check if embedding generation is available
    def self.available?
      new.available?
    end

    def initialize(provider: nil)
      @provider = provider || configured_provider
    end

    def generate(text)
      return nil if text.blank?
      return nil unless available?

      case @provider
      when "openai"
        generate_openai(text)
      when "ollama"
        generate_ollama(text)
      else
        nil
      end
    rescue StandardError => e
      Rails.logger.error("[Memory::Embedding] Failed to generate embedding: #{e.message}")
      nil
    end

    def available?
      case @provider
      when "ollama"
        ollama_reachable?
      when "openai"
        fetch_openai_key.present?
      else
        false
      end
    end

    private

    def configured_provider
      # Embeddings disabled entirely?
      return nil if ENV["MEMORY_EMBEDDINGS_ENABLED"] == "false"

      # Explicit provider from env
      env_provider = ENV["MEMORY_EMBEDDINGS_PROVIDER"]
      return env_provider if env_provider.present?

      # Check app config
      config_provider = Rails.application.config.try(:memory_embedding_provider)
      return config_provider if config_provider.present?

      # Auto-detect: prefer Ollama (free, local), fall back to OpenAI
      if ollama_reachable?
        "ollama"
      elsif fetch_openai_key.present?
        "openai"
      else
        nil
      end
    end

    def generate_ollama(text)
      response = Faraday.post(
        "#{ollama_base_url}/api/embeddings",
        { model: OLLAMA_MODEL, prompt: text }.to_json,
        { "Content-Type" => "application/json" }
      )

      if response.success?
        embedding = JSON.parse(response.body)["embedding"]
        return nil unless embedding.is_a?(Array) && embedding.any?

        # nomic-embed-text natively outputs 768 dims — no padding needed
        embedding.take(DIMENSIONS)
      else
        Rails.logger.error("[Memory::Embedding] Ollama error: #{response.status}")
        nil
      end
    end

    def generate_openai(text)
      api_key = fetch_openai_key
      return nil unless api_key

      response = Faraday.post(
        "https://api.openai.com/v1/embeddings",
        { model: OPENAI_MODEL, input: text, dimensions: DIMENSIONS }.to_json,
        {
          "Authorization" => "Bearer #{api_key}",
          "Content-Type" => "application/json"
        }
      )

      if response.success?
        JSON.parse(response.body).dig("data", 0, "embedding")
      else
        Rails.logger.error("[Memory::Embedding] OpenAI error: #{response.status} #{response.body.truncate(200)}")
        nil
      end
    end

    def ollama_base_url
      provider_config = ProviderConfig.find_by(adapter_type: "ollama", enabled: true)
      provider_config&.base_url || ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
    end

    def ollama_reachable?
      response = Faraday.get("#{ollama_base_url}/api/tags") { |req| req.options.timeout = 2 }
      response.success?
    rescue StandardError
      false
    end

    def fetch_openai_key
      @openai_key ||= VaultEntry.find_by(
        namespace: "provider_credentials",
        key: "openai_api_key"
      )&.encrypted_value
    end
  end
end
