# frozen_string_literal: true

require "net/http"
require "json"

module Providers
  module Anthropic
    class SdkProxyClient
      def initialize(api_key:, base_url:)
        @api_key = api_key
        @base_url = base_url
      end

      def chat(params:, options: {}, &block)
        payload = build_proxy_payload(params, options)

        if block_given?
          stream(payload, &block)
        else
          sync(payload)
        end
      end

      private

      attr_reader :api_key, :base_url

      def build_proxy_payload(params, options = {})
        payload = {
          messages: params[:messages],
          model: params[:model],
          max_tokens: params[:max_tokens],
          system: params[:system]
        }
        payload[:tools] = params[:tools] if params[:tools].present?
        payload[:temperature] = params[:temperature] if params[:temperature]
        payload[:thinking] = params[:thinking] if params[:thinking]
        # Reasoning effort — forwarded for the direct Messages API path in the
        # proxy. The OAuth/Claude-Code path does not consume it yet.
        payload[:effort] = params.dig(:output_config, :effort) if params.dig(:output_config, :effort)

        payload[:agent_id] = options[:agent_id] if options[:agent_id]
        payload[:session_id] = options[:session_id] if options[:session_id]
        payload[:tool_definitions] = options[:tool_definitions] if options[:tool_definitions]
        payload[:memory_dir] = "/app/agents-shared/.hivemind/agents/#{options[:agent_id]}/memory" if options[:agent_id]

        payload
      end

      def sync(payload)
        payload[:stream] = false
        uri = URI("#{base_url}/v1/chat")

        http = Net::HTTP.new(uri.host, uri.port)
        http.read_timeout = 600
        http.open_timeout = 10

        request = Net::HTTP::Post.new(uri.path, {
          "Content-Type" => "application/json",
          "Authorization" => "Bearer #{api_key}"
        })
        request.body = payload.to_json

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          return proxy_failure(status: response.code, body: response.body)
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

      def stream(payload, &block)
        payload[:stream] = true
        uri = URI("#{base_url}/v1/chat")

        full_content = +""
        full_thinking = +""
        usage = {}
        stream_error = nil

        http = Net::HTTP.new(uri.host, uri.port)
        http.read_timeout = 600
        http.open_timeout = 10

        request = Net::HTTP::Post.new(uri.path, {
          "Content-Type" => "application/json",
          "Authorization" => "Bearer #{api_key}"
        })
        request.body = payload.to_json

        stream_error = nil

        http.request(request) do |response|
          unless response.is_a?(Net::HTTPSuccess)
            return proxy_failure(status: response.code, body: response.read_body)
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
              when "thinking_start"
                block.call({ type: "thinking_start" })
              when "thinking"
                text = event_data["thinking"]
                if text
                  full_thinking << text
                  block.call({ type: "thinking", content: text })
                end
              when "thinking_stop"
                block.call({ type: "thinking_stop" })
              when "tool_start"
                block.call({ type: "tool_start", tool: event_data["tool"], input: event_data["input"] })
              when "tool_result"
                block.call({ type: "tool_result", tool: event_data["tool"], output: event_data["output"], success: event_data["success"] })
              when "tool_use"
                # Tool use events in streaming — not typical for our flow but handle gracefully
              when "result"
                usage = event_data["usage"] || {}
              when "error"
                # The proxy classified the failure and sent its verdict as an
                # SSE frame (headers were already flushed, so it could not use
                # an HTTP status). Keep the whole frame, not just the message:
                # the classifier reads `retryable` and `reason` off it, so the
                # caller never has to string-match to decide whether retrying
                # could possibly help.
                stream_error = event_data
              when "done"
                # Stream complete
              end
            end
          end
        end

        # Fail only when the error left us with nothing — if content already
        # streamed, keep the partial reply rather than discarding it. When we
        # do fail, carry the proxy's verdict so the circuit breaker and the
        # job retry policy can act on it.
        if stream_error && full_content.empty?
          return proxy_failure(status: nil, body: stream_error, partial_content: nil)
        end

        thinking = full_thinking.present? ? full_thinking : nil
        ServiceResponse.success(data: { content: full_content, thinking:, usage: })
      end

      # Turn a proxy failure into a ServiceResponse that carries the machine-
      # readable verdict, so callers never have to string-match to decide
      # whether retrying could possibly help.
      def proxy_failure(status:, body:, partial_content: nil)
        error = Providers::ErrorClassifier.call(
          message: proxy_message(status, body),
          status: status&.to_i,
          body: body,
          provider: "anthropic"
        )
        ServiceResponse.failure(
          error: error.message,
          payload: { provider_error: error.to_h, partial_content: partial_content.presence }.compact
        )
      end

      def proxy_message(status, body)
        detail = extract_message(body)
        prefix = status ? "SDK proxy error (#{status})" : "SDK proxy error"
        detail.present? ? "#{prefix}: #{detail}" : prefix
      end

      def extract_message(body)
        parsed = body.is_a?(String) ? (JSON.parse(body) rescue nil) : body
        return body.to_s.truncate(500) unless parsed.is_a?(Hash)

        parsed = parsed.stringify_keys
        nested = parsed["error"]
        nested = nested.stringify_keys["message"] if nested.is_a?(Hash)
        (nested || parsed["message"] || body.to_s).to_s.truncate(500)
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
    end
  end
end
