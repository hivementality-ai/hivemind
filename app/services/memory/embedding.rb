# frozen_string_literal: true

module Memory
  class Embedding
    OPENAI_MODEL = "text-embedding-3-small"
    OLLAMA_MODEL = "nomic-embed-text"
    DIMENSIONS = 1536

    # Generate an embedding vector for the given text.
    # Returns Array[Float] (1536 dims) or nil on failure.
    def self.generate(text, provider: nil)
      new(provider: provider).generate(text)
    end

    def initialize(provider: nil)
      @provider = provider || default_provider
    end

    def generate(text)
      return nil if text.blank?

      case @provider
      when "ollama"
        generate_ollama(text)
      else
        generate_openai(text)
      end
    rescue StandardError => e
      Rails.logger.error("[Memory::Embedding] Failed to generate embedding: #{e.message}")
      nil
    end

    private

    def default_provider
      # Use Ollama if configured and available, otherwise OpenAI
      if ProviderConfig.exists?(adapter_type: "ollama", enabled: true)
        "ollama"
      else
        "openai"
      end
    end

    def generate_openai(text)
      api_key = fetch_openai_key
      return nil unless api_key

      response = Faraday.post(
        "https://api.openai.com/v1/embeddings",
        { model: OPENAI_MODEL, input: text }.to_json,
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

    def generate_ollama(text)
      provider_config = ProviderConfig.find_by(adapter_type: "ollama", enabled: true)
      base_url = provider_config&.base_url || "http://localhost:11434"

      response = Faraday.post(
        "#{base_url}/api/embeddings",
        { model: OLLAMA_MODEL, prompt: text }.to_json,
        { "Content-Type" => "application/json" }
      )

      if response.success?
        embedding = JSON.parse(response.body)["embedding"]
        normalize_dimensions(embedding)
      else
        Rails.logger.error("[Memory::Embedding] Ollama error: #{response.status}")
        nil
      end
    end

    # Pad or truncate to target dimensions for consistent vector storage
    def normalize_dimensions(embedding)
      return nil unless embedding.is_a?(Array)

      if embedding.length < DIMENSIONS
        embedding + Array.new(DIMENSIONS - embedding.length, 0.0)
      elsif embedding.length > DIMENSIONS
        embedding.take(DIMENSIONS)
      else
        embedding
      end
    end

    def fetch_openai_key
      vault_entry = VaultEntry.find_by(
        namespace: "provider_credentials",
        key: "openai_api_key"
      )
      vault_entry&.encrypted_value
    end
  end
end
