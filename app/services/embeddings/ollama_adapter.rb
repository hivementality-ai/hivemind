# frozen_string_literal: true

module Embeddings
  class OllamaAdapter < BaseAdapter
    MODEL = "nomic-embed-text"

    def capabilities
      {
        name: "ollama",
        modalities: [ :text ],
        dimensions: [ 768 ],
        default_dimensions: 768,
        max_tokens: 2048,
        local: true,
        task_types: [ :retrieval_query, :retrieval_document ]
      }
    end

    def embed_text(text, dimensions: nil)
      response = Faraday.post(
        "#{base_url}/api/embeddings",
        { model: model_name, prompt: text, options: { num_ctx: 2048 } }.to_json,
        { "Content-Type" => "application/json" }
      )

      return nil unless response.success?

      embedding = JSON.parse(response.body)["embedding"]
      return nil unless embedding.is_a?(Array) && embedding.any?

      dims = dimensions || configured_dimensions
      embedding.take(dims)
    end

    def healthy?
      response = Faraday.get("#{base_url}/api/tags") { |req| req.options.timeout = 2 }
      response.success?
    rescue StandardError
      false
    end

    private

    def base_url
      provider_config = ProviderConfig.find_by(adapter_type: "ollama", enabled: true)
      provider_config&.base_url || ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
    end

    def model_name
      ENV.fetch("MEMORY_OLLAMA_MODEL", MODEL)
    end
  end
end
