# frozen_string_literal: true

require "faraday"
require "json"
require "securerandom"

module Providers
  module Anthropic
    # Direct HTTP client for the Anthropic Messages API.
    #
    # Bypasses the official `anthropic` gem so we can attach the Claude Code
    # OAuth headers ("You are Claude Code, Anthropic's official CLI for Claude."
    # plus `anthropic-beta: oauth-2025-04-20`) when the token is an OAuth token.
    # When the same pattern is ported from the rubyn-code project, the OAuth
    # token unlocks the Claude Code quota against the plain `/v1/messages`
    # endpoint — no sidecar, no SDK subprocess.
    #
    # Also applies three prompt-caching breakpoints (system, tools, last
    # message) so the conversation prefix is cached across turns.
    class FaradayClient
      API_URL = "https://api.anthropic.com/v1/messages"
      ANTHROPIC_VERSION = "2023-06-01"
      # Same OAuth beta + claude-code-20250219 (Claude Code session beta) so the
      # gateway routes through the Claude Code quota path the same way the CLI
      # does. Mirrors openclaw/openclaw's anthropic-transport-stream.ts.
      OAUTH_BETA = "claude-code-20250219,oauth-2025-04-20"
      OAUTH_USER_AGENT = "claude-code/2.1.79"
      OAUTH_GATE = "You are Claude Code, Anthropic's official CLI for Claude."
      # 1-hour TTL is supported on direct api.anthropic.com (and Vertex). Paying
      # ~2× per cache write buys 12× the cache window — net win for any session
      # with idle gaps > 5 minutes, which is most chat workloads.
      CACHE_EPHEMERAL = { type: "ephemeral", ttl: "1h" }.freeze

      def initialize(api_key:)
        @api_key = api_key
      end

      def chat(params:, options: {}, &block)
        body = build_body(params, stream: block_given?)

        if block_given?
          stream_request(body, &block)
        else
          sync_request(body)
        end
      rescue Faraday::Error => e
        ServiceResponse.failure(error: "Anthropic API error: #{e.message}")
      end

      private

      attr_reader :api_key

      def oauth?
        api_key.to_s.start_with?("sk-ant-oat")
      end

      # ─── Request body ────────────────────────────────────────────────

      def build_body(params, stream:)
        body = {
          model: params[:model],
          max_tokens: params[:max_tokens]
        }

        body[:temperature] = params[:temperature] if params[:temperature]
        body[:thinking] = params[:thinking] if params[:thinking]

        apply_system_blocks(body, params[:system])
        apply_tool_cache(body, params[:tools])
        body[:messages] = add_message_cache_breakpoint(params[:messages] || [])
        body[:stream] = true if stream

        body
      end

      # System-section caching (matches rubyn-code's two-breakpoint OAuth
      # strategy). Anthropic allows a max of 4 cache_control markers per
      # request and caches everything up to and including a marker, so we
      # place at most 2 markers in system:
      #
      #   1. OAUTH_GATE (OAuth only) — cached independently so it survives
      #      any change to the caller's system prompt.
      #   2. The last caller system block — caches OAUTH_GATE + every
      #      caller block as one prefix.
      #
      # This reserves 2 of the 4 markers for tools (breakpoint 3) and the
      # last message (breakpoint 4), hitting the Anthropic cap exactly.
      def apply_system_blocks(body, system)
        caller_blocks = []
        Array(system).each do |entry|
          if entry.is_a?(Hash)
            text = entry[:text] || entry["text"]
            next if text.to_s.strip.empty?
            caller_blocks << { type: "text", text: text.to_s }
          elsif entry.is_a?(String) && !entry.strip.empty?
            caller_blocks << { type: "text", text: entry }
          end
        end

        blocks = []
        if oauth?
          blocks << { type: "text", text: OAUTH_GATE, cache_control: CACHE_EPHEMERAL }
        end
        blocks.concat(caller_blocks)

        return if blocks.empty?

        # Tier-2 marker: caches the full system prefix (OAUTH_GATE +
        # every caller block). Falls on OAUTH_GATE itself if no caller
        # blocks exist — the assignment is idempotent.
        blocks.last[:cache_control] = CACHE_EPHEMERAL
        body[:system] = blocks
      end

      # Breakpoint 2: tool definitions. Anthropic caches the prefix up to the
      # most recent breakpoint, so a marker on the last tool covers them all.
      def apply_tool_cache(body, tools)
        return if tools.nil? || tools.empty?

        cached = tools.map(&:dup)
        cached.last[:cache_control] = CACHE_EPHEMERAL
        body[:tools] = cached
      end

      # Breakpoint 3: last message. The cache captures the entire conversation
      # prefix, so subsequent turns only pay for the new round-trip.
      def add_message_cache_breakpoint(messages)
        return messages if messages.empty?

        tagged = messages.map { |m| deep_stringify_symbol_keys(m).dup }
        tag_last_message_content(tagged.last)
        tagged
      end

      def tag_last_message_content(last_msg)
        content = last_msg[:content] || last_msg["content"]

        case content
        when Array
          return if content.empty?
          duped = content.map(&:dup)
          last_block = duped.last
          last_block[:cache_control] = CACHE_EPHEMERAL if last_block.is_a?(Hash)
          assign_content(last_msg, duped)
        when String
          assign_content(last_msg, [ { type: "text", text: content, cache_control: CACHE_EPHEMERAL } ])
        end
      end

      def assign_content(msg, value)
        if msg.key?(:content)
          msg[:content] = value
        else
          msg["content"] = value
        end
      end

      def deep_stringify_symbol_keys(value)
        value
      end

      # ─── HTTP ────────────────────────────────────────────────────────

      def connection
        @connection ||= Faraday.new do |f|
          f.options.timeout = 600
          f.options.open_timeout = 30
          f.adapter Faraday.default_adapter
        end
      end

      def apply_headers(req)
        req.headers["Content-Type"] = "application/json"
        req.headers["anthropic-version"] = ANTHROPIC_VERSION

        if oauth?
          req.headers["Authorization"] = "Bearer #{api_key}"
          req.headers["anthropic-beta"] = OAUTH_BETA
          req.headers["User-Agent"] = OAUTH_USER_AGENT
          req.headers["x-app"] = "cli"
          req.headers["X-Claude-Code-Session-Id"] = session_id
          req.headers["anthropic-dangerous-direct-browser-access"] = "true"
        else
          req.headers["x-api-key"] = api_key
        end
      end

      def session_id
        @session_id ||= SecureRandom.uuid
      end

      # ─── Sync ────────────────────────────────────────────────────────

      def sync_request(body)
        log_outbound(body)
        response = connection.post(API_URL) do |req|
          apply_headers(req)
          req.body = JSON.generate(body)
        end

        log_inbound(response.status, response.body)

        unless response.success?
          err = parse_error_body(response.body)
          return ServiceResponse.failure(error: "Anthropic API error (#{response.status}): #{err}")
        end

        parsed = JSON.parse(response.body)
        ServiceResponse.success(data: build_sync_data(parsed))
      end

      # ─── Debug logging (gated by Setting "prompt_debug_enabled") ─────

      def prompt_debug?
        Setting.get("prompt_debug_enabled") == "true"
      rescue StandardError
        false
      end

      def log_outbound(body)
        return unless prompt_debug?
        Rails.logger.info("[Anthropic→] POST #{API_URL} oauth=#{oauth?} body=\n#{JSON.pretty_generate(body)}")
      rescue StandardError => e
        Rails.logger.warn("[Anthropic→] log_outbound failed: #{e.message}")
      end

      def log_inbound(status, body)
        return unless prompt_debug?
        snippet = body.to_s
        snippet = snippet[0..10_000] + "\n…[truncated #{snippet.length} bytes]" if snippet.length > 10_000
        Rails.logger.info("[Anthropic←] status=#{status} body=\n#{snippet}")
      rescue StandardError => e
        Rails.logger.warn("[Anthropic←] log_inbound failed: #{e.message}")
      end

      def build_sync_data(body)
        content = nil
        thinking = nil
        tool_calls = []

        Array(body["content"]).each do |block|
          case block["type"]
          when "text"
            content = block["text"]
          when "thinking"
            thinking = block["thinking"] if block["thinking"]
          when "tool_use"
            tool_calls << {
              "id" => block["id"],
              "name" => block["name"],
              "input" => (block["input"] || {}).to_h
            }
          end
        end

        tool_calls = nil if tool_calls.empty?

        {
          content: content,
          thinking: thinking,
          tool_calls: tool_calls,
          usage: parse_usage(body["usage"])
        }
      end

      def parse_usage(data)
        return {} unless data

        {
          input_tokens: data["input_tokens"],
          output_tokens: data["output_tokens"],
          cache_creation_input_tokens: data["cache_creation_input_tokens"],
          cache_read_input_tokens: data["cache_read_input_tokens"]
        }.compact
      end

      def parse_error_body(body)
        return body.to_s[0..500] if body.nil? || body.empty?
        parsed = JSON.parse(body)
        parsed.dig("error", "message") || body.to_s[0..500]
      rescue JSON::ParserError
        body.to_s[0..500]
      end

      # ─── Streaming (SSE) ─────────────────────────────────────────────

      def stream_request(body, &block)
        log_outbound(body)
        streamer = StreamParser.new(&block)
        error_chunks = []

        response = connection.post(API_URL) do |req|
          apply_headers(req)
          req.body = JSON.generate(body)
          req.options.on_data = proc do |chunk, _size, env|
            if env.status == 200
              streamer.feed(chunk)
            else
              error_chunks << chunk
            end
          end
        end

        unless response.status == 200
          log_inbound(response.status, error_chunks.join)
          err = parse_error_body(error_chunks.join)
          return ServiceResponse.failure(error: "Anthropic API error (#{response.status}): #{err}")
        end

        data = streamer.finalize
        log_stream_summary(data) if prompt_debug?
        ServiceResponse.success(data: data)
      end

      def log_stream_summary(data)
        content_len = data[:content].to_s.length
        tool_count = Array(data[:tool_calls]).size
        usage = data[:usage] || {}
        Rails.logger.info("[Anthropic←] stream done content_chars=#{content_len} tool_calls=#{tool_count} usage=#{usage.inspect}")
      rescue StandardError => e
        Rails.logger.warn("[Anthropic←] log_stream_summary failed: #{e.message}")
      end

      # Inline SSE parser that maps Anthropic stream events to hivemind's
      # existing chunk contract: { type:, content: / input: / output: ... }.
      class StreamParser
        def initialize(&block)
          @callback = block
          @buffer = +""
          @full_text = +""
          @full_thinking = +""
          @tool_calls = []
          @current_block = nil
          @current_tool_input_json = +""
          @usage = {}
        end

        def feed(chunk)
          @buffer << chunk
          while (idx = @buffer.index("\n\n"))
            raw = @buffer.slice!(0..(idx + 1))
            process_event(raw)
          end
        end

        def finalize
          tool_calls = @tool_calls.empty? ? nil : @tool_calls
          {
            content: @full_text.dup,
            thinking: @full_thinking.empty? ? nil : @full_thinking.dup,
            tool_calls: tool_calls,
            usage: @usage
          }
        end

        private

        def process_event(raw)
          event_type = nil
          data_lines = []

          raw.each_line do |line|
            line = line.chomp
            if line.start_with?("event:")
              event_type = line.sub(/\Aevent:\s*/, "").strip
            elsif line.start_with?("data:")
              data_lines << line.sub(/\Adata:\s*/, "")
            end
          end

          return if event_type.nil? || data_lines.empty?

          data = parse_json(data_lines.join("\n"))
          return unless data

          dispatch(event_type, data)
        end

        def dispatch(event_type, data)
          case event_type
          when "message_start"
            usage = data.dig("message", "usage")
            merge_usage(usage) if usage
          when "content_block_start"
            block = data["content_block"] || {}
            @current_block = block["type"]
            case @current_block
            when "thinking"
              @callback&.call({ type: "thinking_start" })
            when "tool_use"
              @current_tool_id = block["id"]
              @current_tool_name = block["name"]
              @current_tool_input_json = +""
            end
          when "content_block_delta"
            delta = data["delta"] || {}
            case delta["type"]
            when "text_delta"
              text = delta["text"] || ""
              @full_text << text
              @callback&.call({ type: "content", content: text })
            when "thinking_delta"
              text = delta["thinking"] || ""
              @full_thinking << text
              @callback&.call({ type: "thinking", content: text })
            when "input_json_delta"
              @current_tool_input_json << (delta["partial_json"] || "")
            end
          when "content_block_stop"
            if @current_block == "thinking"
              @callback&.call({ type: "thinking_stop" })
            elsif @current_block == "tool_use" && @current_tool_id
              input = parse_json(@current_tool_input_json) || {}
              @tool_calls << {
                "id" => @current_tool_id,
                "name" => @current_tool_name,
                "input" => input.to_h
              }
              @current_tool_id = nil
              @current_tool_name = nil
              @current_tool_input_json = +""
            end
            @current_block = nil
          when "message_delta"
            merge_usage(data["usage"]) if data["usage"]
          end
        end

        def merge_usage(usage)
          return unless usage
          @usage[:input_tokens] = usage["input_tokens"] if usage["input_tokens"]
          @usage[:output_tokens] = usage["output_tokens"] if usage["output_tokens"]
          @usage[:cache_creation_input_tokens] = usage["cache_creation_input_tokens"] if usage["cache_creation_input_tokens"]
          @usage[:cache_read_input_tokens] = usage["cache_read_input_tokens"] if usage["cache_read_input_tokens"]
        end

        def parse_json(str)
          return nil if str.nil? || str.empty?
          JSON.parse(str)
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
