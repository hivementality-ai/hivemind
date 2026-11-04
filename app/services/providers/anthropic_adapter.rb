# frozen_string_literal: true

module Providers
  class AnthropicAdapter < Base
    SDK_PROXY_URL = ENV.fetch("SDK_PROXY_URL", "http://sdk-proxy:3003")
    CACHE_BREAKPOINT = { type: "ephemeral" }.freeze
    # Anthropic allows four cache_control breakpoints per request: one on the
    # last tool, one on the last message, leaving two for the system prompt.
    MAX_SYSTEM_BREAKPOINTS = 2
    UNCACHEABLE_BLOCK_TYPES = %w[thinking redacted_thinking].freeze

    def chat(messages:, tools: [], options: {}, &block)
      params = build_chat_params(messages:, tools:, options:)

      # The circuit gate goes outside everything, including the memory-sync
      # enqueue: when it is open nothing at all happens on this credential.
      with_circuit_breaker do
        begin
          result = if oauth_token? && sdk_proxy_enabled?
            sync_memories_for_oauth(messages, options)
            proxy_client.chat(params:, options: options.merge(system_dynamic: dynamic_system_text(messages)), &block)
          else
            faraday_client.chat(params:, options:, &block)
          end

          inject_request_payload(result, params)
        rescue AgentInterrupted, AgentRedirected, PromptTooLongError
          raise
        rescue ProviderError => e
          # Already classified downstream — keep the verdict intact.
          with_provider_error(ServiceResponse.failure(error: "Anthropic API error: #{e.message}"), e)
        rescue StandardError => e
          ServiceResponse.failure(error: "Anthropic API error: #{e.message}")
        end
      end
    end

    def models
      model_list = LlmModelRegistry.supported_for_provider("anthropic").map(&:api_id)
      ServiceResponse.success(data: { models: model_list })
    end

    def embed(text:, model: nil)
      ServiceResponse.failure(error: "Anthropic does not support embeddings")
    end

    private

    def oauth_token?
      api_key&.start_with?("sk-ant-oat")
    end

    def sdk_proxy_enabled?
      self.class.sdk_proxy_enabled?
    end

    # OAuth (sk-ant-oat) tokens route through the SDK proxy by DEFAULT so chats
    # consume the Claude subscription's included usage via Claude Code, rather
    # than the direct API path which bills against pay-as-you-go "extra usage"
    # and fails with "You're out of extra usage" once that allowance is spent.
    #
    # An explicit Setting (anthropic_use_sdk_proxy, toggleable from the provider
    # edit page) or ENV (USE_SDK_PROXY_FALLBACK) can force either path — set it
    # to "false" to opt back into the direct API. Absent both, the proxy is on.
    # Only consulted for OAuth tokens; API keys always go direct.
    def self.sdk_proxy_enabled?
      val = Setting.get("anthropic_use_sdk_proxy")
      return val == "true" if val.present?
      # Default ON; the ENV escape hatch only needs to force it back off.
      ENV["USE_SDK_PROXY_FALLBACK"] != "false"
    rescue StandardError
      true
    end

    def sync_memories_for_oauth(messages, options)
      return unless options[:agent_id]
      # Run async so memory sync doesn't block the chat response
      MemoryFileSyncJob.perform_later(options[:agent_id], query: messages.last&.dig(:content) || messages.last&.dig("content"))
    rescue StandardError => e
      Rails.logger.warn("[AnthropicAdapter] Memory sync enqueue failed: #{e.message}")
    end

    def faraday_client
      @faraday_client ||= Anthropic::FaradayClient.new(api_key:)
    end

    # Text of the per-turn system block Rails flags as dynamic, so the proxy can
    # keep a warm process across turns. Never sent to the Messages API.
    def dynamic_system_text(messages)
      system_msg = messages.find { |m| (m[:role] || m["role"]).to_s == "system" }
      content = system_msg && (system_msg[:content] || system_msg["content"])
      return unless content.is_a?(Array)

      block = content.last&.to_h&.with_indifferent_access
      block[:text].presence if block && block[:dynamic]
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
        model: options[:model] || LlmModelRegistry::Anthropic::DEFAULT_MID,
        messages: formatted_msgs,
        max_tokens: options[:max_tokens] || 8192
      }

      system_content = system_msg&.dig(:content) || system_msg&.dig("content")
      if system_content.present?
        params[:system] = build_cached_system(system_content)
      end

      if tools.any?
        # Sorted by name so the tools prefix is byte-identical from turn to turn.
        params[:tools] = tools.sort_by { |t| t[:name].to_s }.map do |t|
          { name: t[:name], description: t[:description], input_schema: t[:input_schema] }
        end
        params[:tools].last[:cache_control] = CACHE_BREAKPOINT.dup
      end

      mark_last_message_for_cache(params[:messages])

      params[:temperature] = options[:temperature] if options[:temperature]

      if options[:thinking_enabled]
        budget = options[:thinking_budget_tokens] || 10_000
        params[:thinking] = { type: "enabled", budget_tokens: budget }
        params.delete(:temperature)
        params[:max_tokens] = [ params[:max_tokens] || 8192, budget + 4096 ].max
      end

      # Reasoning effort (output_config.effort) — supported on Opus 4.5+, Sonnet
      # 4.6, Sonnet 5, and Fable 5; errors on Haiku / Sonnet 4.5, so gate by model.
      if options[:effort].present? && effort_supported?(params[:model])
        params[:output_config] = (params[:output_config] || {}).merge(effort: options[:effort].to_s)
      end

      params
    end

    # Whether the given model accepts output_config.effort.
    def effort_supported?(model)
      model.to_s.match?(/claude-(?:opus-5|opus-4-[5678]|sonnet-5|sonnet-4-6|fable-5)/)
    end

    # Builds the system blocks with at most MAX_SYSTEM_BREAKPOINTS breakpoints:
    # the last block (end of the whole prompt) and the longest earlier block,
    # which is the stable core or skills text. Blocks after the stable ones
    # (memory, addons) change per turn, so the earlier breakpoint keeps the big
    # stable prefix cached when they do.
    def build_cached_system(content)
      texts = if content.is_a?(Array)
                content.map { |block| block.to_h.with_indifferent_access[:text].to_s }
      else
                [ content.to_s ]
      end
      texts = texts.reject(&:blank?)

      marked = [ texts.size - 1 ]
      marked << texts[0...-1].each_index.max_by { |i| texts[i].length } if texts.size > 1

      texts.each_with_index.map do |text, i|
        block = { type: "text", text: text }
        block[:cache_control] = CACHE_BREAKPOINT.dup if marked.include?(i)
        block
      end
    end

    # Puts a breakpoint on the last content block of the last message so the
    # next turn reuses the whole conversation so far. String content becomes a
    # single text block; blocks are copied so the caller's hashes stay untouched.
    def mark_last_message_for_cache(messages)
      last = messages.last
      return unless last

      content = last[:content]
      if content.is_a?(String)
        return if content.blank?

        last[:content] = [ { type: "text", text: content, cache_control: CACHE_BREAKPOINT.dup } ]
      elsif content.is_a?(Array) && content.any?
        block = content.last.to_h
        return if UNCACHEABLE_BLOCK_TYPES.include?((block[:type] || block["type"]).to_s)

        last[:content] = content[0...-1] + [ block.merge(cache_control: CACHE_BREAKPOINT.dup) ]
      end
    end
  end
end
