# frozen_string_literal: true

module Embeddings
  class OpenaiAdapter < BaseAdapter
    MODEL = "text-embedding-3-small"

    def capabilities
      {
        name: "openai",
        modalities: [:text],
        dimensions: [256, 512, 768, 1536, 3072],
        default_dimensions: 768,
        max_tokens: 8191,
        local: false,
        task_types: [:retrieval_query, :retrieval_document]
      }
    end

    def embed_text(text, dimensions: nil)
      key = api_key
      return nil unless key

      dims = dimensions || configured_dimensions

      response = Faraday.post(
        "https://api.openai.com/v1/embeddings",
        { model: model_name, input: text, dimensions: dims }.to_json,
        {
          "Authorization" => "Bearer #{key}",
          "Content-Type" => "application/json"
        }
      )

      return nil unless response.success?

      JSON.parse(response.body).dig("data", 0, "embedding")
    end

    def healthy?
      api_key.present?
    end

    def cost_per_million_tokens
      0.02
    end

    private

    def api_key
      @api_key ||= VaultEntry.find_by(
        namespace: "provider_credentials",
        key: "openai_api_key"
      )&.value
    end

    def model_name
      ENV.fetch("MEMORY_OPENAI_MODEL", MODEL)
    end
  end
end
