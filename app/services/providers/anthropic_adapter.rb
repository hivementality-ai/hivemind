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
    rescue StandardError => e
      ServiceResponse.failure(error: "Anthropic API error: #{e.message}")
    end

    def models
      model_list = %w[claude-haiku-4-5 claude-sonnet-4-5 claude-opus-4]
      ServiceResponse.success(data: { models: model_list })
    end

    def embed(text:, model: nil)
      ServiceResponse.failure(error: "Anthropic does not support embeddings")
    end

    private

    def build_client
      if oauth_token?
        Anthropic::Client.new(auth_token: api_key)
      else
        Anthropic::Client.new(api_key:)
      end
    end

    def oauth_request_options
      return {} unless oauth_token?

      {
        extra_headers: {
          "anthropic-beta" => "claude-code-20250219,oauth-2025-04-20",
          "anthropic-dangerous-direct-browser-access" => "true"
        }
      }
    end

    def oauth_token?
      api_key&.start_with?("sk-ant-oat")
    end

    def build_chat_params(messages:, tools:, options:)
      # Separate system message from conversation messages
      system_msg = messages.find { |m| m[:role]&.to_s == "system" || m["role"]&.to_s == "system" }
      chat_msgs = messages.reject { |m| (m[:role] || m["role"])&.to_s == "system" }

      # Format messages for Anthropic API
      formatted_msgs = chat_msgs.map do |m|
        m = m.to_h.with_indifferent_access
        role = m[:role].to_s

        if role == "tool"
          { role: "user", content: [{ type: "tool_result", tool_use_id: m[:tool_use_id], content: m[:content].to_s }] }
        elsif role == "assistant" && m[:tool_calls].present?
          content = []
          content << { type: "text", text: m[:content] } if m[:content].present?
          m[:tool_calls].each do |tc|
            content << { type: "tool_use", id: tc["id"], name: tc["name"], input: tc["input"] || {} }
          end
          { role: "assistant", content: content }
        else
          { role: role, content: m[:content].to_s }
        end
      end

      params = {
        model: options[:model] || "claude-sonnet-4-5",
        messages: formatted_msgs,
        max_tokens: options[:max_tokens] || 8192
      }

      system_content = system_msg&.dig(:content) || system_msg&.dig("content")
      params[:system] = system_content.to_s if system_content.present?

      if tools.any?
        params[:tools] = tools.map do |t|
          { name: t[:name], description: t[:description], input_schema: t[:input_schema] }
        end
      end

      params[:temperature] = options[:temperature] if options[:temperature]
      params
    end

    def stream_chat(client:, params:, &block)
      full_content = +""
      usage = {}

      params[:request_options] = oauth_request_options if oauth_token?
      stream = client.messages.stream(**params)

      stream.each do |event|
        case event.type.to_s
        when "content_block_delta"
          if event.delta.respond_to?(:text) && event.delta.text
            full_content << event.delta.text
            block.call({ type: "content", content: event.delta.text })
          end
        when "message_start"
          if event.message.respond_to?(:usage) && event.message.usage
            usage[:input_tokens] = event.message.usage.input_tokens
          end
        when "message_delta"
          if event.respond_to?(:usage) && event.usage
            usage[:output_tokens] = event.usage.output_tokens
          end
        end
      end

      ServiceResponse.success(data: { content: full_content, usage: })
    end

    def sync_chat(client:, params:)
      params[:request_options] = oauth_request_options if oauth_token?
      response = client.messages.create(**params)

      content = nil
      tool_calls = []

      response.content.each do |block|
        case block.type.to_s
        when "text"
          content = block.text
        when "tool_use"
          tool_calls << { "id" => block.id, "name" => block.name, "input" => block.input.to_h }
        end
      end

      usage = {
        input_tokens: response.usage&.input_tokens,
        output_tokens: response.usage&.output_tokens
      }

      tool_calls = nil if tool_calls.empty?

      ServiceResponse.success(data: { content:, tool_calls:, usage: })
    end
  end
end
