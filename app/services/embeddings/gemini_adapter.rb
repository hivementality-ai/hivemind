# frozen_string_literal: true

module Embeddings
  class GeminiAdapter < BaseAdapter
    API_BASE = "https://generativelanguage.googleapis.com/v1beta/models"
    MODEL = "gemini-embedding-exp-03-07"

    def capabilities
      {
        name: "gemini",
        modalities: [ :text, :image, :audio, :video, :pdf ],
        dimensions: [ 768, 1536, 3072 ],
        default_dimensions: 768,
        max_tokens: 8192,
        local: false,
        task_types: [
          :retrieval_query, :retrieval_document, :semantic_similarity,
          :classification, :clustering, :question_answering,
          :fact_verification, :code_retrieval
        ]
      }
    end

    def embed_text(text, dimensions: nil)
      call_api(
        content: { parts: [ { text: text } ] },
        task_type: "RETRIEVAL_DOCUMENT",
        dimensions: dimensions
      )
    end

    def embed_query(text, dimensions: nil)
      call_api(
        content: { parts: [ { text: text } ] },
        task_type: "RETRIEVAL_QUERY",
        dimensions: dimensions
      )
    end

    def embed_image(base64_data, mime_type:, dimensions: nil)
      call_api(
        content: { parts: [ { inlineData: { mimeType: mime_type, data: base64_data } } ] },
        dimensions: dimensions
      )
    end

    # Embed interleaved multimodal content (text + images + audio + video + documents).
    # Each part is a hash with one of:
    #   { text: "..." }
    #   { image: "<base64>", mime_type: "image/png" }
    #   { audio: "<base64>", mime_type: "audio/mp3" }
    #   { video: "<base64>", mime_type: "video/mp4" }
    #   { document: "<base64>", mime_type: "application/pdf" }
    def embed_multimodal(parts, dimensions: nil)
      api_parts = parts.filter_map do |part|
        if part[:text]
          { text: part[:text] }
        elsif part[:image]
          { inlineData: { mimeType: part[:mime_type], data: part[:image] } }
        elsif part[:audio]
          { inlineData: { mimeType: part[:mime_type], data: part[:audio] } }
        elsif part[:video]
          { inlineData: { mimeType: part[:mime_type], data: part[:video] } }
        elsif part[:document]
          { inlineData: { mimeType: part[:mime_type], data: part[:document] } }
        end
      end

      call_api(content: { parts: api_parts }, dimensions: dimensions)
    end

    def healthy?
      api_key.present?
    end

    def cost_per_million_tokens
      0.10
    end

    private

    def call_api(content:, task_type: nil, dimensions: nil)
      key = api_key
      return nil unless key

      dims = dimensions || configured_dimensions
      body = {
        model: "models/#{model_name}",
        content: content,
        outputDimensionality: dims
      }
      body[:taskType] = task_type if task_type

      response = Faraday.post(
        "#{API_BASE}/#{model_name}:embedContent?key=#{key}",
        body.to_json,
        { "Content-Type" => "application/json" }
      )

      return nil unless response.success?

      JSON.parse(response.body).dig("embedding", "values")
    end

    def api_key
      @api_key ||= ENV["GOOGLE_AI_API_KEY"] || VaultEntry.find_by(
        namespace: "provider_credentials",
        key: "google_ai_api_key"
      )&.value
    end

    def model_name
      ENV.fetch("MEMORY_GEMINI_MODEL", MODEL)
    end
  end
end
