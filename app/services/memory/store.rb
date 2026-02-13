# frozen_string_literal: true

module Memory
  class Store
    def self.call(agent:, content:, source: nil, metadata: {})
      new(agent:, content:, source:, metadata:).call
    end

    def initialize(agent:, content:, source: nil, metadata: {})
      @agent = agent
      @content = content
      @source = source
      @metadata = metadata
    end

    def call
      return ServiceResponse.failure(error: "Content cannot be blank") if @content.blank?

      embedding = generate_embedding(@content)
      return ServiceResponse.failure(error: "Failed to generate embedding") unless embedding

      memory_entry = MemoryEntry.create(
        agent: @agent,
        content: @content,
        embedding: embedding,
        source: @source,
        metadata: @metadata
      )

      if memory_entry.persisted?
        ServiceResponse.success(data: { memory_entry: })
      else
        ServiceResponse.failure(error: memory_entry.errors.full_messages)
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Memory storage failed: #{e.message}")
    end

    private

    def generate_embedding(text)
      # Get the provider configuration for the agent
      provider = @agent.model_provider || "openai"
      
      case provider
      when "openai"
        generate_openai_embedding(text)
      when "anthropic"
        # Anthropic doesn't provide embeddings yet, fallback to OpenAI
        generate_openai_embedding(text)
      when "ollama"
        generate_ollama_embedding(text)
      else
        generate_openai_embedding(text) # Default fallback
      end
    end

    def generate_openai_embedding(text)
      # Use OpenAI's text-embedding-3-small model (1536 dimensions)
      vault_entry = VaultEntry.find_by(
        namespace: "provider_credentials",
        key: "openai_api_key"
      )
      
      return nil unless vault_entry

      api_key = vault_entry.encrypted_value
      
      response = Faraday.post(
        "https://api.openai.com/v1/embeddings",
        { model: "text-embedding-3-small", input: text }.to_json,
        {
          "Authorization" => "Bearer #{api_key}",
          "Content-Type" => "application/json"
        }
      )

      if response.success?
        result = JSON.parse(response.body)
        result.dig("data", 0, "embedding")
      else
        Rails.logger.error("OpenAI embedding failed: #{response.body}")
        nil
      end
    rescue StandardError => e
      Rails.logger.error("OpenAI embedding error: #{e.message}")
      nil
    end

    def generate_ollama_embedding(text)
      # Use Ollama's embedding endpoint (default model: nomic-embed-text)
      provider_config = ProviderConfig.find_by(adapter_type: "ollama", enabled: true)
      base_url = provider_config&.base_url || "http://localhost:11434"
      
      response = Faraday.post(
        "#{base_url}/api/embeddings",
        { model: "nomic-embed-text", prompt: text }.to_json,
        { "Content-Type" => "application/json" }
      )

      if response.success?
        result = JSON.parse(response.body)
        embedding = result["embedding"]
        
        # Pad or truncate to 1536 dimensions to match OpenAI format
        if embedding.length < 1536
          embedding + Array.new(1536 - embedding.length, 0.0)
        else
          embedding.take(1536)
        end
      else
        Rails.logger.error("Ollama embedding failed: #{response.body}")
        nil
      end
    rescue StandardError => e
      Rails.logger.error("Ollama embedding error: #{e.message}")
      nil
    end
  end
end
