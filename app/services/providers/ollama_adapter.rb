# frozen_string_literal: true

module Providers
  class OllamaAdapter < Base
    def chat(messages:, tools: [], options: {}, &block)
      params = build_chat_params(messages:, tools:, options:)

      if block_given?
        stream_chat(params:, &block)
      else
        sync_chat(params:)
      end
    rescue Faraday::Error => e
      ServiceResponse.failure(error: "Ollama error: #{e.message}")
    end

    def models
      response = connection.get("/api/tags")
      body = JSON.parse(response.body)
      model_list = body["models"]&.map { |m| m["name"] } || []
      ServiceResponse.success(data: { models: model_list })
    rescue Faraday::Error => e
      ServiceResponse.failure(error: "Failed to list models: #{e.message}")
    end

    def embed(text:, model: nil)
      model ||= "nomic-embed-text"
      response = connection.post("/api/embeddings") do |req|
        req.body = { model:, prompt: text }.to_json
      end
      body = JSON.parse(response.body)
      ServiceResponse.success(data: { embedding: body["embedding"] })
    rescue Faraday::Error => e
      ServiceResponse.failure(error: "Embedding error: #{e.message}")
    end

    private

    def connection
      @connection ||= Faraday.new(url: ollama_url) do |f|
        f.request :json
        f.response :raise_error
        f.adapter Faraday.default_adapter
      end
    end

    def ollama_url
      base_url || "http://localhost:11434"
    end

    def build_chat_params(messages:, tools:, options:)
      {
        model: options[:model] || "llama3.2",
        messages: messages.map { |m| m.slice(:role, :content) },
        stream: false,
        options: {
          temperature: options[:temperature],
          num_predict: options[:max_tokens]
        }.compact
      }
    end

    def stream_chat(params:, &block)
      full_content = +""

      response = connection.post("/api/chat") do |req|
        req.body = params.merge(stream: true).to_json
      end

      response.body.each_line do |line|
        next if line.strip.empty?

        chunk = JSON.parse(line)
        if chunk["message"]&.dig("content")
          delta = chunk["message"]["content"]
          full_content << delta
          block.call({ type: "content", content: delta })
        end
      end

      # Ollama doesn't report token usage in streaming — estimate
      ServiceResponse.success(data: { content: full_content, usage: {} })
    end

    def sync_chat(params:)
      response = connection.post("/api/chat") do |req|
        req.body = params.to_json
      end

      body = JSON.parse(response.body)
      content = body.dig("message", "content")
      usage = {
        input_tokens: body.dig("prompt_eval_count"),
        output_tokens: body.dig("eval_count")
      }

      ServiceResponse.success(data: { content:, usage: })
    end
  end
end
