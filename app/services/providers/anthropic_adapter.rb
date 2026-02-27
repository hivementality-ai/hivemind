# frozen_string_literal: true

require "net/http"
require "json"

module Providers
  class AnthropicAdapter < Base
    SDK_PROXY_URL = ENV.fetch("SDK_PROXY_URL", "http://sdk-proxy:3003")

    def chat(messages:, tools: [], options: {}, &block)
      if oauth_token?
        sdk_proxy_chat(messages:, tools:, options:, &block)
      else
        gem_chat(messages:, tools:, options:, &block)
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

    # ─── Key type detection ───

    def oauth_token?
      api_key&.start_with?("sk-ant-oat")
    end

    # ─── Path 1: Anthropic Ruby Gem (API keys) ───

    def gem_chat(messages:, tools: [], options: {}, &block)
      client = Anthropic::Client.new(api_key:)
      params = build_chat_params(messages:, tools:, options:)

      if block_given?
        gem_stream_chat(client:, params:, &block)
      else
        gem_sync_chat(client:, params:)
      end
    end

    def gem_stream_chat(client:, params:, &block)
      full_content = +""
      full_thinking = +""
      current_block_type = nil
      usage = {}
      usage[:request_payload] = sanitize_payload_for_logging(params)

      stream = client.messages.stream(**params)

      stream.each do |event|
        case event.type.to_s
        when "content_block_start"
          if event.respond_to?(:content_block)
            current_block_type = event.content_block.type.to_s
            block.call({ type: "thinking_start" }) if current_block_type == "thinking"
          end
        when "content_block_delta"
          if current_block_type == "thinking" && event.delta.respond_to?(:thinking) && event.delta.thinking
            full_thinking << event.delta.thinking
            block.call({ type: "thinking", content: event.delta.thinking })
          elsif event.delta.respond_to?(:text) && event.delta.text
            full_content << event.delta.text
            block.call({ type: "content", content: event.delta.text })
          end
        when "content_block_stop"
          block.call({ type: "thinking_stop" }) if current_block_type == "thinking"
          current_block_type = nil
        when "message_start"
          if event.message.respond_to?(:usage) && event.message.usage
            u = event.message.usage
            usage[:input_tokens] = u.input_tokens
            usage[:cache_creation_input_tokens] = u.respond_to?(:cache_creation_input_tokens) ? u.cache_creation_input_tokens : nil
            usage[:cache_read_input_tokens] = u.respond_to?(:cache_read_input_tokens) ? u.cache_read_input_tokens : nil
          end
        when "message_delta"
          if event.respond_to?(:usage) && event.usage
            usage[:output_tokens] = event.usage.output_tokens
          end
        end
      end

      thinking = full_thinking.present? ? full_thinking : nil
      ServiceResponse.success(data: { content: full_content, thinking:, usage: })
    end

    def gem_sync_chat(client:, params:)
      response = client.messages.create(**params)

      content = nil
      thinking = nil
      tool_calls = []

      response.content.each do |block|
        case block.type.to_s
        when "thinking"
          thinking = block.thinking if block.respond_to?(:thinking)
        when "text"
          content = block.text
        when "tool_use"
          tool_calls << { "id" => block.id, "name" => block.name, "input" => block.input.to_h.stringify_keys }
        end
      end

      usage = {
        input_tokens: response.usage&.input_tokens,
        output_tokens: response.usage&.output_tokens,
        cache_creation_input_tokens: response.usage&.respond_to?(:cache_creation_input_tokens) ? response.usage.cache_creation_input_tokens : nil,
        cache_read_input_tokens: response.usage&.respond_to?(:cache_read_input_tokens) ? response.usage.cache_read_input_tokens : nil,
        request_payload: sanitize_payload_for_logging(params)
      }

      tool_calls = nil if tool_calls.empty?

      ServiceResponse.success(data: { content:, thinking:, tool_calls:, usage: })
    end

    # ─── Path 2: SDK Proxy (OAuth tokens) ───

    def sdk_proxy_chat(messages:, tools: [], options: {}, &block)
      params = build_chat_params(messages:, tools:, options:)
      payload = build_proxy_payload(params)

      if block_given?
        sdk_proxy_stream(payload, &block)
      else
        sdk_proxy_sync(payload)
      end
    end

    def build_proxy_payload(params)
      payload = {
        messages: params[:messages],
        model: params[:model],
        max_tokens: params[:max_tokens],
        system: params[:system]
      }
      payload[:tools] = params[:tools] if params[:tools].present?
      payload[:temperature] = params[:temperature] if params[:temperature]
      payload[:thinking] = params[:thinking] if params[:thinking]
      payload
    end

    def sdk_proxy_sync(payload)
      payload[:stream] = false
      uri = URI("#{SDK_PROXY_URL}/v1/chat")

      http = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = 120
      http.open_timeout = 10

      request = Net::HTTP::Post.new(uri.path, {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{api_key}"
      })
      request.body = payload.to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        return ServiceResponse.failure(error: "SDK proxy error (#{response.code}): #{response.body}")
      end

      data = JSON.parse(response.body, symbolize_names: true)

      tool_calls = data[:tool_calls]&.map do |tc|
        { "id" => tc[:id], "name" => tc[:name], "input" => (tc[:input] || {}).stringify_keys }
      end

      ServiceResponse.success(data: {
        content: data[:content],
        thinking: data[:thinking],
        tool_calls: tool_calls,
        usage: data[:usage] || {}
      })
    end

    def sdk_proxy_stream(payload, &block)
      payload[:stream] = true
      uri = URI("#{SDK_PROXY_URL}/v1/chat")

      full_content = +""
      full_thinking = +""
      usage = {}

      http = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = 120
      http.open_timeout = 10

      request = Net::HTTP::Post.new(uri.path, {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{api_key}"
      })
      request.body = payload.to_json

      http.request(request) do |response|
        unless response.is_a?(Net::HTTPSuccess)
          body = response.read_body
          return ServiceResponse.failure(error: "SDK proxy error (#{response.code}): #{body}")
        end

        buffer = +""
        response.read_body do |chunk|
          buffer << chunk
          while (line_end = buffer.index("\n\n"))
            frame = buffer.slice!(0, line_end + 2)
            event_type, event_data = parse_sse_frame(frame)
            next unless event_type && event_data

            case event_type
            when "content"
              text = event_data["content"]
              if text
                full_content << text
                block.call({ type: "content", content: text })
              end
            when "thinking"
              text = event_data["thinking"]
              if text
                full_thinking << text
                block.call({ type: "thinking", content: text })
              end
            when "tool_use"
              # Tool use events in streaming — not typical for our flow but handle gracefully
            when "result"
              usage = event_data["usage"] || {}
            when "done"
              # Stream complete
            end
          end
        end
      end

      thinking = full_thinking.present? ? full_thinking : nil
      ServiceResponse.success(data: { content: full_content, thinking:, usage: })
    end

    def parse_sse_frame(frame)
      event_type = nil
      data_line = nil

      frame.each_line do |line|
        line = line.strip
        if line.start_with?("event: ")
          event_type = line.sub("event: ", "")
        elsif line.start_with?("data: ")
          data_line = line.sub("data: ", "")
        end
      end

      return nil unless event_type && data_line

      [ event_type, JSON.parse(data_line) ]
    rescue JSON::ParserError
      nil
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

    def sanitize_payload_for_logging(params)
      payload = params.deep_dup
      if payload[:messages].is_a?(Array)
        payload[:messages] = payload[:messages].map do |msg|
          msg = msg.dup
          if msg[:content].is_a?(String) && msg[:content].length > 2000
            msg[:content] = msg[:content][0..2000] + "... [truncated #{msg[:content].length} chars]"
          elsif msg[:content].is_a?(Array)
            msg[:content] = msg[:content].map do |block|
              block = block.dup
              if block[:text].is_a?(String) && block[:text].length > 2000
                block[:text] = block[:text][0..2000] + "... [truncated #{block[:text].length} chars]"
              end
              block
            end
          end
          msg
        end
      end
      payload.except(:request_options)
    rescue StandardError => e
      { error: "Failed to capture payload: #{e.message}" }
    end
  end
end
