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

        payload[:agent_id] = options[:agent_id] if options[:agent_id]
        payload[:session_id] = options[:session_id] if options[:session_id]
        payload[:tool_definitions] = options[:tool_definitions] if options[:tool_definitions]

        payload
      end

      def sync(payload)
        payload[:stream] = false
        uri = URI("#{base_url}/v1/chat")

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

      def stream(payload, &block)
        payload[:stream] = true
        uri = URI("#{base_url}/v1/chat")

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
    end
  end
end
