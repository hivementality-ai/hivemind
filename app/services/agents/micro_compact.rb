# frozen_string_literal: true

module Agents
  # Replaces the content of older tool messages with short placeholders so
  # long-running sessions stop paying the full tool-output cost on every
  # turn. Keeps the most recent `keep_recent` tool messages intact so the
  # LLM still sees fresh results.
  #
  # Ported from rubyn-code's Context::MicroCompact, adapted for hivemind's
  # `{role: "tool", ...}` message shape.
  module MicroCompact
    PLACEHOLDER_TEMPLATE = "[Previous: used %<tool_name>s]"
    MIN_CONTENT_LENGTH = 100

    class << self
      # Mutates +messages+ in place. Returns number of entries compacted.
      def call(messages, keep_recent: 2, preserve_tools: [])
        tool_refs = collect_tool_messages(messages)
        return 0 if tool_refs.size <= keep_recent

        candidates = tool_refs[0..-(keep_recent + 1)]
        compacted = 0

        candidates.each do |msg|
          compacted += 1 if compact_one(msg, preserve_tools)
        end

        compacted
      end

      private

      def collect_tool_messages(messages)
        messages.select { |m| (m[:role] || m["role"]).to_s == "tool" }
      end

      def compact_one(msg, preserve_tools)
        content = msg[:content] || msg["content"]
        return false if content.nil?

        content_str = content.to_s
        return false if content_str.length < MIN_CONTENT_LENGTH

        tool_name = (msg[:tool_name] || msg["tool_name"]).to_s
        return false if tool_name.empty?
        return false if preserve_tools.include?(tool_name)
        return false if content_str.start_with?("[Previous:")

        placeholder = format(PLACEHOLDER_TEMPLATE, tool_name: tool_name)
        assign_content(msg, placeholder)
        true
      end

      def assign_content(msg, value)
        if msg.key?(:content)
          msg[:content] = value
        else
          msg["content"] = value
        end
      end
    end
  end
end
