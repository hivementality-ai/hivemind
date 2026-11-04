# frozen_string_literal: true

module Providers
  module Anthropic
    class GemClient
      def chat(client:, params:, &block)
        if block_given?
          stream_chat(client:, params:, &block)
        else
          sync_chat(client:, params:)
        end
      end

      private

      def stream_chat(client:, params:, &block)
        full_content = +""
        full_thinking = +""
        current_block_type = nil
        usage = {}
        tool_calls = []
        current_tool = nil

        stream = client.messages.stream(**params)

        stream.each do |event|
          case event.type.to_s
          when "content_block_start"
            if event.respond_to?(:content_block)
              current_block_type = event.content_block.type.to_s
              block.call({ type: "thinking_start" }) if current_block_type == "thinking"
              if current_block_type == "tool_use"
                current_tool = { id: event.content_block.id, name: event.content_block.name, json: +"" }
              end
            end
          when "content_block_delta"
            if current_block_type == "tool_use"
              current_tool[:json] << event.delta.partial_json.to_s if current_tool && event.delta.respond_to?(:partial_json)
            elsif current_block_type == "thinking" && event.delta.respond_to?(:thinking) && event.delta.thinking
              full_thinking << event.delta.thinking
              block.call({ type: "thinking", content: event.delta.thinking })
            elsif event.delta.respond_to?(:text) && event.delta.text
              full_content << event.delta.text
              block.call({ type: "content", content: event.delta.text })
            end
          when "content_block_stop"
            block.call({ type: "thinking_stop" }) if current_block_type == "thinking"
            if current_block_type == "tool_use" && current_tool
              tool_calls << { "id" => current_tool[:id], "name" => current_tool[:name], "input" => parse_tool_input(current_tool[:json]) }
              current_tool = nil
            end
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
        ServiceResponse.success(data: { content: full_content, thinking:, tool_calls: tool_calls.presence, usage: })
      end

      def parse_tool_input(json)
        return {} if json.blank?

        JSON.parse(json)
      rescue JSON::ParserError
        {}
      end

      def sync_chat(client:, params:)
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
          cache_read_input_tokens: response.usage&.respond_to?(:cache_read_input_tokens) ? response.usage.cache_read_input_tokens : nil
        }

        tool_calls = nil if tool_calls.empty?

        ServiceResponse.success(data: { content:, thinking:, tool_calls:, usage: })
      end
    end
  end
end
