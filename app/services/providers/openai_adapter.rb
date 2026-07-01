# frozen_string_literal: true

module Providers
  class OpenaiAdapter < Base
    def chat(messages:, tools: [], options: {}, &block)
      client = build_client
      params = build_chat_params(messages:, tools:, options:)

      if block_given?
        stream_chat(client:, params:, &block)
      else
        sync_chat(client:, params:)
      end
    rescue Faraday::Error => e
      ServiceResponse.failure(error: "OpenAI API error: #{e.message}")
    end

    def models
      client = build_client
      response = client.models.list
      model_list = response.dig("data")&.map { |m| m["id"] } || []
      ServiceResponse.success(data: { models: model_list })
    rescue Faraday::Error => e
      ServiceResponse.failure(error: "Failed to list models: #{e.message}")
    end

    def embed(text:, model: nil)
      client = build_client
      model ||= "text-embedding-3-small"
      response = client.embeddings(parameters: { model:, input: text })
      embedding = response.dig("data", 0, "embedding")
      ServiceResponse.success(data: { embedding: })
    rescue Faraday::Error => e
      ServiceResponse.failure(error: "Embedding error: #{e.message}")
    end

    private

    def build_client
      OpenAI::Client.new(
        access_token: api_key,
        uri_base: base_url || "https://api.openai.com/v1"
      )
    end

    def build_chat_params(messages:, tools:, options:)
      # Format messages for OpenAI API
      # If system content is an array of blocks (from structured prompt), join text
      formatted = messages.map do |m|
        m = m.to_h.with_indifferent_access
        if m[:role] == "system" && m[:content].is_a?(Array)
          joined = m[:content].map { |b| b.to_h.with_indifferent_access[:text].to_s }.reject(&:blank?).join("\n\n")
          next { role: "system", content: joined }
        end
        if m[:role] == "tool"
          { role: "tool", tool_call_id: m[:tool_use_id], content: m[:content].to_s }
        elsif m[:role] == "assistant" && m[:tool_calls].present?
          openai_tool_calls = m[:tool_calls].map do |tc|
            { id: tc["id"], type: "function", function: { name: tc["name"], arguments: (tc["input"] || {}).to_json } }
          end
          msg = { role: "assistant", content: m[:content] || "" }
          msg[:tool_calls] = openai_tool_calls
          msg
        elsif m[:content].is_a?(Array)
          # Multimodal content — convert Anthropic format to OpenAI format
          openai_content = m[:content].map do |block|
            block = block.to_h.with_indifferent_access
            case block[:type]
            when "image"
              { type: "image_url", image_url: { url: "data:#{block.dig(:source, :media_type)};base64,#{block.dig(:source, :data)}" } }
            when "text"
              { type: "text", text: block[:text] }
            else
              { type: "text", text: block.to_s }
            end
          end
          { role: m[:role], content: openai_content }
        else
          m.slice(:role, :content)
        end
      end

      params = {
        model: options[:model] || LlmModelRegistry::OpenAI::DEFAULT_TOP,
        messages: formatted
      }

      # Convert tools to OpenAI function format
      if tools.any?
        params[:tools] = tools.map do |t|
          { type: "function", function: { name: t[:name], description: t[:description], parameters: t[:input_schema] } }
        end
      end
      params[:temperature] = options[:temperature] if options[:temperature]

      if options[:thinking_enabled]
        model = options[:model] || params[:model]
        if model&.match?(/\b(o[1-9]|o3|o4)/i)
          params[:reasoning_effort] = "high"
          params.delete(:temperature) # Not compatible with reasoning
        end
      end

      if options[:max_tokens]
        # GPT-5+ and o-series models require max_completion_tokens instead of max_tokens
        model = options[:model] || params[:model]
        if model&.match?(/\b(gpt-5|gpt-audio|gpt-realtime|o[1-9]|o3|o4)/i)
          params[:max_completion_tokens] = options[:max_tokens]
        else
          params[:max_tokens] = options[:max_tokens]
        end
      end
      params
    end

    def stream_chat(client:, params:, &block)
      full_content = +""
      usage = {}

      client.chat(parameters: params.merge(stream: proc { |chunk|
        delta = chunk.dig("choices", 0, "delta", "content")
        if delta
          full_content << delta
          block.call({ type: "content", content: delta })
        end

        if chunk["usage"]
          cached = chunk.dig("usage", "prompt_tokens_details", "cached_tokens")
          usage = {
            input_tokens: chunk["usage"]["prompt_tokens"],
            output_tokens: chunk["usage"]["completion_tokens"]
          }
          usage[:cached_input_tokens] = cached if cached && cached > 0
        end
      }))

      result = ServiceResponse.success(data: { content: full_content, usage: })
      inject_request_payload(result, params)
    end

    def sync_chat(client:, params:)
      response = client.chat(parameters: params)
      content = response.dig("choices", 0, "message", "content")
      raw_tool_calls = response.dig("choices", 0, "message", "tool_calls")
      cached = response.dig("usage", "prompt_tokens_details", "cached_tokens")
      usage = {
        input_tokens: response.dig("usage", "prompt_tokens"),
        output_tokens: response.dig("usage", "completion_tokens")
      }
      usage[:cached_input_tokens] = cached if cached && cached > 0

      # Normalize OpenAI tool calls to our internal format
      tool_calls = raw_tool_calls&.map do |tc|
        {
          "id" => tc["id"],
          "name" => tc.dig("function", "name"),
          "input" => JSON.parse(tc.dig("function", "arguments") || "{}")
        }
      end

      result = ServiceResponse.success(data: { content:, tool_calls:, usage: })
      inject_request_payload(result, params)
    end
  end
end
