# frozen_string_literal: true

require "securerandom"

module Providers
  class OpenaiCompatibleAdapter < Base
    def chat(messages:, tools: [], options: {}, &block)
      with_circuit_breaker do
        params = build_chat_params(messages:, tools:, options:)

        if block_given?
          stream_chat(params:, &block)
        else
          sync_chat(params:)
        end
      rescue Faraday::Error => e
        ServiceResponse.failure(error: "OpenAI-compatible API error: #{e.message}")
      end
    end

    def models
      response = connection.get("/v1/models")
      body = JSON.parse(response.body)
      model_list = body["data"]&.map { |m| m["id"] } || []
      ServiceResponse.success(data: { models: model_list })
    rescue Faraday::Error => e
      ServiceResponse.failure(error: "Failed to list models: #{e.message}")
    end

    def embed(text:, model: nil)
      model ||= "default"
      response = connection.post("/v1/embeddings") do |req|
        req.body = { model:, input: text }.to_json
      end
      body = JSON.parse(response.body)
      embedding = body.dig("data", 0, "embedding")
      ServiceResponse.success(data: { embedding: })
    rescue Faraday::Error => e
      ServiceResponse.failure(error: "Embedding error: #{e.message}")
    end

    private

    def connection
      @connection ||= Faraday.new(url: server_url) do |f|
        f.request :json
        if api_key.present?
          f.request :authorization, "Bearer", api_key
        end
        f.response :raise_error
        f.options.open_timeout = 10
        f.options.timeout = 600
        f.adapter Faraday.default_adapter
      end
    end

    def server_url
      url = base_url.presence
      raise "OpenAI-compatible provider '#{config.name}' (id=#{config.id}) has no base_url configured" unless url
      url
    end

    def build_chat_params(messages:, tools:, options:)
      formatted_messages = messages.map do |m|
        m = m.to_h.with_indifferent_access
        role = m[:role].to_s
        content = flatten_content(m[:content])

        if role == "tool"
          msg = { role: "tool", content: content.to_s }
          msg[:tool_call_id] = m[:tool_call_id] || m[:tool_use_id] if m[:tool_call_id].present? || m[:tool_use_id].present?
          msg
        elsif role == "assistant" && m[:tool_calls].present?
          openai_tool_calls = m[:tool_calls].map do |tc|
            args = tc["input"] || {}
            args = args.to_json unless args.is_a?(String)
            {
              id: tc["id"] || "call_#{SecureRandom.hex(4)}",
              type: "function",
              function: { name: tc["name"], arguments: args }
            }
          end
          msg = { role: "assistant", content: content || "" }
          msg[:tool_calls] = openai_tool_calls
          msg
        else
          { role: role, content: content }
        end
      end

      params = {
        model: options[:model] || "default",
        messages: formatted_messages,
        stream: false
      }

      params[:temperature] = options[:temperature] if options[:temperature]
      params[:max_tokens] = options[:max_tokens] if options[:max_tokens]

      if options[:thinking_enabled]
        params[:reasoning_format] = "deepseek"
        params.delete(:temperature)
      end

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

    # OpenAI-compatible APIs require content to be a plain string.
    # Flatten Anthropic-style content blocks (arrays of {type: "text", text: "..."})
    # into a single string.
    def flatten_content(content)
      return content unless content.is_a?(Array)

      content.map { |b|
        b = b.to_h.with_indifferent_access
        b[:text].presence || b[:content].presence
      }.compact.reject(&:blank?).join("\n\n")
    end

    # Strip <think>...</think> tags from content, returning [clean_content, thinking]
    def extract_think_tags(text)
      return [ text, nil ] if text.blank?

      thinking_parts = []
      clean = text.gsub(/<think>(.*?)<\/think>/m) do
        thinking_parts << ::Regexp.last_match(1).strip
        ""
      end
      [ clean.strip, thinking_parts.any? ? thinking_parts.join("\n\n") : nil ]
    end

    def stream_chat(params:, &block)
      # Fall back to sync when tools are present
      if params[:tools].present?
        result = sync_chat(params:)
        if result.success?
          content = result.data[:content]
          content&.each_char { |char| block.call({ type: "content", content: char }) }
        end
        return result
      end

      full_content = +""
      full_thinking = +""
      thinking_started = false
      in_think_tag = false
      content_buffer = +""

      streaming_conn = Faraday.new(url: server_url) do |f|
        f.request :json
        if api_key.present?
          f.request :authorization, "Bearer", api_key
        end
        f.options.open_timeout = 10
        f.options.timeout = 600
        f.adapter Faraday.default_adapter
      end

      buffer = +""

      streaming_conn.post("/v1/chat/completions") do |req|
        req.body = params.merge(stream: true).to_json
        req.options.on_data = proc do |chunk, _overall_received_bytes, _env|
          buffer << chunk
          while (line_end = buffer.index("\n"))
            line = buffer.slice!(0..line_end).strip
            next if line.empty?
            next unless line.start_with?("data: ")

            data = line.sub(/\Adata: /, "")
            next if data == "[DONE]"

            begin
              parsed = JSON.parse(data)

              reasoning = parsed.dig("choices", 0, "delta", "reasoning_content")
              if reasoning
                unless thinking_started
                  block.call({ type: "thinking_start" })
                  thinking_started = true
                end
                full_thinking << reasoning
                block.call({ type: "thinking", content: reasoning })
              end

              delta = parsed.dig("choices", 0, "delta", "content")
              if delta
                if thinking_started
                  block.call({ type: "thinking_stop" })
                  thinking_started = false
                end

                # Buffer content to detect and strip <think> tags
                content_buffer << delta

                # Process complete <think>...</think> blocks
                while content_buffer.include?("</think>")
                  before, _, after = content_buffer.partition(/<think>.*?<\/think>/m)
                  think_match = content_buffer.match(/<think>(.*?)<\/think>/m)
                  if think_match
                    full_thinking << think_match[1]
                    # Emit any content before the think block
                    if before.present?
                      full_content << before
                      block.call({ type: "content", content: before })
                    end
                    content_buffer = after
                  else
                    break
                  end
                end

                # If we have an open <think> tag, keep buffering
                if content_buffer.include?("<think>") && !content_buffer.include?("</think>")
                  in_think_tag = true
                  before = content_buffer.split("<think>", 2).first
                  if before.present?
                    full_content << before
                    block.call({ type: "content", content: before })
                    content_buffer = content_buffer.sub(before, "")
                  end
                elsif !in_think_tag && !content_buffer.match?(/<?$/) # avoid partial tag
                  # Safe to flush — no partial tag at end
                  safe = content_buffer.sub(/<[^>]*\z/, "")
                  remainder = content_buffer[safe.length..]
                  if safe.present?
                    full_content << safe
                    block.call({ type: "content", content: safe })
                  end
                  content_buffer = remainder || +""
                end
              end
            rescue JSON::ParserError
              next
            end
          end
        end
      end

      # Flush any remaining buffered content
      if content_buffer.present?
        cleaned, inline_thinking = extract_think_tags(content_buffer)
        full_thinking << inline_thinking if inline_thinking
        if cleaned.present?
          full_content << cleaned
          block.call({ type: "content", content: cleaned })
        end
      end

      thinking = full_thinking.presence

      result = ServiceResponse.success(data: { content: full_content, thinking:, usage: {} })
      inject_request_payload(result, params)
    end

    def sync_chat(params:)
      response = connection.post("/v1/chat/completions") do |req|
        req.body = params.to_json
      end

      body = JSON.parse(response.body)
      choice = body.dig("choices", 0, "message")
      content = choice&.dig("content")
      thinking = choice&.dig("reasoning_content").presence

      # Some models (e.g. Minimax) embed thinking in <think> tags within content
      content, inline_thinking = extract_think_tags(content)
      thinking ||= inline_thinking
      raw_tool_calls = choice&.dig("tool_calls")

      tool_calls = raw_tool_calls&.map do |tc|
        args = tc.dig("function", "arguments") || "{}"
        args = JSON.parse(args) if args.is_a?(String) rescue args

        {
          "id" => tc["id"] || "oai_compat_#{SecureRandom.hex(4)}",
          "name" => tc.dig("function", "name"),
          "input" => args
        }
      end

      tool_calls = nil if tool_calls&.empty?

      usage_data = body["usage"] || {}
      usage = {
        input_tokens: usage_data["prompt_tokens"],
        output_tokens: usage_data["completion_tokens"]
      }

      result = ServiceResponse.success(data: { content:, thinking:, tool_calls:, usage: })
      inject_request_payload(result, params)
    end
  end
end
