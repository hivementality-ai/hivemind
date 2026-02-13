# frozen_string_literal: true

module Memory
  class Search
    def self.call(agent:, query:, limit: 10, threshold: 0.7)
      new(agent:, query:, limit:, threshold:).call
    end

    def initialize(agent:, query:, limit: 10, threshold: 0.7)
      @agent = agent
      @query = query
      @limit = limit
      @threshold = threshold
    end

    def call
      return ServiceResponse.failure(error: "Query cannot be blank") if @query.blank?

      query_embedding = generate_embedding(@query)
      return ServiceResponse.failure(error: "Failed to generate query embedding") unless query_embedding

      results = MemoryEntry.search_with_threshold(
        embedding: query_embedding,
        agent: @agent,
        threshold: @threshold,
        limit: @limit
      )

      # Enrich results with similarity scores
      enriched_results = results.map do |entry|
        {
          id: entry.id,
          content: entry.content,
          similarity: (1 - entry.neighbor_distance).round(4),
          source_type: entry.source_type,
          source_id: entry.source_id,
          metadata: entry.metadata,
          created_at: entry.created_at
        }
      end

      ServiceResponse.success(data: { 
        query: @query,
        results: enriched_results,
        count: enriched_results.length
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Memory search failed: #{e.message}")
    end

    private

    def generate_embedding(text)
      # Reuse the same logic from Memory::Store
      # In production, this could be extracted to a shared service
      provider = @agent.model_provider || "openai"
      
      case provider
      when "openai"
        generate_openai_embedding(text)
      when "anthropic"
        generate_openai_embedding(text)
      when "ollama"
        generate_ollama_embedding(text)
      else
        generate_openai_embedding(text)
      end
    end

    def generate_openai_embedding(text)
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
        nil
      end
    rescue StandardError => e
      Rails.logger.error("OpenAI embedding error: #{e.message}")
      nil
    end

    def generate_ollama_embedding(text)
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
        
        # Pad or truncate to 1536 dimensions
        if embedding.length < 1536
          embedding + Array.new(1536 - embedding.length, 0.0)
        else
          embedding.take(1536)
        end
      else
        nil
      end
    rescue StandardError => e
      Rails.logger.error("Ollama embedding error: #{e.message}")
      nil
    end
  end
end
