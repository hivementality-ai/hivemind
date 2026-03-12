# frozen_string_literal: true

module Providers
  class AnthropicAdapter < Base
    SDK_PROXY_URL = ENV.fetch("SDK_PROXY_URL", "http://sdk-proxy:3003")

    def chat(messages:, tools: [], options: {}, &block)
      params = build_chat_params(messages:, tools:, options:)

      if oauth_token?
        proxy_client.chat(params:, options:, &block)
      else
        result = gem_client.chat(client: ::Anthropic::Client.new(api_key:), params:, &block)
        inject_request_payload(result, params)
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Anthropic API error: #{e.message}")
    end

    def models
      model_list = %w[claude-haiku-4-5 claude-sonnet-4-5 claude-opus-4-6]
      ServiceResponse.success(data: { models: model_list })
    end

    def embed(text:, model: nil)
      ServiceResponse.failure(error: "Anthropic does not support embeddings")
    end

    private

    def oauth_token?
      api_key&.start_with?("sk-ant-oat")
    end

    def gem_client
      @gem_client ||= Anthropic::GemClient.new
    end

    def proxy_client
      @proxy_client ||= Anthropic::SdkProxyClient.new(api_key:, base_url: SDK_PROXY_URL)
    end

    # ─── Shared helpers ───

    def build_chat_params(messages:, tools:, options:)
      system_msg = messages.find { |m| m[:role]&.to_s == "system" || m["role"]&.to_s == "system" }
      chat_msgs = messages.reject { |m| (m[:role] || m["role"])&.to_s == "system" }

      formatted_msgs = chat_msgs.map do |m|
        m = m.to_h.with_indifferent_access
        role = m[:role].to_s

        if role == "tool"
          { role: "user", content: [ { type: "tool_result", tool_use_id: m[:tool_use_id], content: m[:content].to_s } ] }
        elsif role == "assistant" && m[:tool_calls].present?
          content = []
          content << { type: "text", text: m[:content] } if m[:content].present?
          m[:tool_calls].each do |tc|
            content << { type: "tool_use", id: tc["id"], name: tc["name"], input: tc["input"] || {} }
          end
          { role: "assistant", content: content }
        elsif m[:content].is_a?(Array)
          { role: role, content: m[:content] }
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
      if system_content.present?
        params[:system] = build_cached_system(system_content)
      end

      if tools.any?
        params[:tools] = tools.map do |t|
          { name: t[:name], description: t[:description], input_schema: t[:input_schema] }
        end
      end

      params[:temperature] = options[:temperature] if options[:temperature]

      if options[:thinking_enabled]
        budget = options[:thinking_budget_tokens] || 10_000
        params[:thinking] = { type: "enabled", budget_tokens: budget }
        params.delete(:temperature)
        params[:max_tokens] = [ params[:max_tokens] || 8192, budget + 4096 ].max
      end

      params
    end

    def build_cached_system(content)
      blocks = if content.is_a?(Array)
                 content.map do |block|
                   b = block.to_h.with_indifferent_access
                   { type: "text", text: b[:text].to_s, cache_control: { type: "ephemeral" } }
                 end
      else
                 [ { type: "text", text: content.to_s, cache_control: { type: "ephemeral" } } ]
      end
      blocks.reject { |b| b[:text].blank? }
    end
  end
end
