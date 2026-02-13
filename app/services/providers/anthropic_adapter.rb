# frozen_string_literal: true

module Providers
  class AnthropicAdapter < Base
    def chat(messages:, tools: [], options: {}, &block)
      client = build_client
      params = build_chat_params(messages:, tools:, options:)

      if block_given?
        stream_chat(client:, params:, &block)
      else
        sync_chat(client:, params:)
      end
    rescue Faraday::Error => e
      ServiceResponse.failure(error: "Anthropic API error: #{e.message}")
    end

    def models
      # Anthropic doesn't have a models list endpoint — return known models
      model_list = %w[
        claude-haiku-4-5
        claude-sonnet-4-5
        claude-opus-4
      ]
      ServiceResponse.success(data: { models: model_list })
    end

    def embed(text:, model: nil)
      # Anthropic doesn't offer embeddings — fall back to another provider
      ServiceResponse.failure(error: "Anthropic does not support embeddings")
    end

    private

    def build_client
      Anthropic::Client.new(
        api_key:,
        api_url: base_url || "https://api.anthropic.com"
      )
    end

    def build_chat_params(messages:, tools:, options:)
      # Separate system message from conversation messages
      system_msg = messages.find { |m| m[:role] == "system" }
      chat_msgs = messages.reject { |m| m[:role] == "system" }

      params = {
        model: options[:model] || "claude-sonnet-4-5",
        messages: chat_msgs.map { |m| m.slice(:role, :content) },
        max_tokens: options[:max_tokens] || 8192
      }

      params[:system] = system_msg[:content] if system_msg
      params[:tools] = tools if tools.any?
      params[:temperature] = options[:temperature] if options[:temperature]
      params
    end

    def stream_chat(client:, params:, &block)
      full_content = +""
      usage = {}

      client.messages(
        parameters: params.merge(
          stream: proc { |event|
            if event["type"] == "content_block_delta"
              delta = event.dig("delta", "text")
              if delta
                full_content << delta
                block.call({ type: "content", content: delta })
              end
            end

            if event["type"] == "message_delta" && event.dig("usage")
              usage[:output_tokens] = event.dig("usage", "output_tokens")
            end

            if event["type"] == "message_start" && event.dig("message", "usage")
              usage[:input_tokens] = event.dig("message", "usage", "input_tokens")
            end
          }
        )
      )

      ServiceResponse.success(data: { content: full_content, usage: })
    end

    def sync_chat(client:, params:)
      response = client.messages(parameters: params)
      content = response.dig("content", 0, "text")
      tool_calls = response["content"]&.select { |c| c["type"] == "tool_use" }
      usage = {
        input_tokens: response.dig("usage", "input_tokens"),
        output_tokens: response.dig("usage", "output_tokens")
      }

      ServiceResponse.success(data: { content:, tool_calls:, usage: })
    end
  end
end
