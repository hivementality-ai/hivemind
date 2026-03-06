# frozen_string_literal: true

require "securerandom"

module Providers
  class OllamaAdapter < Base
    CONTEXT_BUCKETS = [ 2_048, 4_096, 8_192, 16_384, 32_768, 65_536, 131_072 ].freeze
    TOKENS_PER_CHAR = 0.25
    CONTEXT_HEADROOM = 1.25 # 25% buffer
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
      base_url || ENV.fetch("OLLAMA_URL", "http://host.docker.internal:11434")
    end

    def build_chat_params(messages:, tools:, options:)
      # Format messages for Ollama API
      formatted_messages = messages.map do |m|
        m = m.to_h.with_indifferent_access
        role = m[:role].to_s
        content = flatten_content(m[:content])

        if role == "tool"
          msg = { role: "tool", content: content.to_s }
          # Ollama requires tool_name to match results back to calls
          msg[:tool_name] = m[:tool_name] if m[:tool_name].present?
          msg
        elsif role == "assistant" && m[:tool_calls].present?
          ollama_tool_calls = m[:tool_calls].map do |tc|
            { function: { name: tc["name"], arguments: tc["input"] || {} } }
          end
          msg = { role: "assistant", content: content || "" }
          msg[:tool_calls] = ollama_tool_calls
          msg
        else
          { role: role, content: content }
        end
      end

      params = {
        model: options[:model] || "llama3.2",
        messages: formatted_messages,
        stream: false,
        options: {
          temperature: options[:temperature],
          num_predict: options[:max_tokens],
          num_ctx: calculate_num_ctx(formatted_messages, tools, options)
        }.compact
      }

      # Convert tools to Ollama format if provided
      if tools.any?
        params[:tools] = tools.map do |t|
          {
            type: "function",
            function: {
              name: t[:name],
              description: t[:description],
              parameters: t[:input_schema]
            }
          }
        end
      end

      params
    end

    # Ollama requires content to be a plain string.
    # Flatten Anthropic-style content blocks (arrays of {type: "text", text: "..."})
    # and image blocks into a single string.
    def flatten_content(content)
      return content unless content.is_a?(Array)

      content.map { |b|
        b = b.to_h.with_indifferent_access
        b[:text].presence || b[:content].presence
      }.compact.reject(&:blank?).join("\n\n")
    end

    def calculate_num_ctx(messages, tools, options)
      char_count = messages.sum { |m| m[:content].to_s.length }
      char_count += tools.to_json.length if tools.any?
      estimated_tokens = (char_count * TOKENS_PER_CHAR * CONTEXT_HEADROOM).ceil
      estimated_tokens += (options[:max_tokens] || 4_096)
      CONTEXT_BUCKETS.find { |s| s >= estimated_tokens } || CONTEXT_BUCKETS.last
    end

    def stream_chat(params:, &block)
      # If tools are present, fall back to sync mode since tool calls
      # come at the end and we need the full response
      if params[:tools].present?
        result = sync_chat(params: params)
        if result.success?
          content = result.data[:content]
          content&.each_char { |char| block.call({ type: "content", content: char }) }
        end
        return result
      end

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
      raw_tool_calls = body.dig("message", "tool_calls")

      # Normalize tool calls to match expected format
      tool_calls = raw_tool_calls&.map do |tc|
        args = tc.dig("function", "arguments") || {}
        # Some models return stringified JSON for arguments
        args = JSON.parse(args) if args.is_a?(String) rescue args

        {
          "id" => "ollama_#{SecureRandom.hex(4)}",
          "name" => tc.dig("function", "name"),
          "input" => args
        }
      end

      tool_calls = nil if tool_calls&.empty?

      usage = {
        input_tokens: body.dig("prompt_eval_count"),
        output_tokens: body.dig("eval_count")
      }

      ServiceResponse.success(data: { content:, tool_calls:, usage: })
    end
  end
end
