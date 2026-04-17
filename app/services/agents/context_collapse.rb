# frozen_string_literal: true

require "json"

module Agents
  # Client-side context reduction — no LLM summarization call. Keeps the
  # first message, the first real user message, and the most recent
  # `keep_recent` messages; replaces the middle with a snip marker.
  #
  # Ported from rubyn-code's Context::ContextCollapse.
  module ContextCollapse
    SNIP_MARKER = "[%d earlier messages snipped for context efficiency]"
    CHARS_PER_TOKEN = 4

    class << self
      # Returns a collapsed copy of messages if the estimated token count of
      # the result is under `threshold`. Returns nil if collapse alone would
      # not bring the context under budget (caller should fall back to a
      # hard prune).
      def call(messages, threshold:, keep_recent: 6)
        return nil if messages.nil? || messages.size <= keep_recent + 2

        anchors = build_anchors(messages)
        recent = messages.last(keep_recent)
        snipped_count = messages.size - keep_recent - anchors.size
        return nil if snipped_count <= 0

        collapsed = [
          *anchors,
          { "role" => "user", "content" => format(SNIP_MARKER, snipped_count) },
          *recent
        ]

        estimated = (JSON.generate(collapsed).length.to_f / CHARS_PER_TOKEN).ceil
        estimated <= threshold ? collapsed : nil
      rescue JSON::GeneratorError
        nil
      end

      private

      def build_anchors(messages)
        first = messages.first
        anchors = [ first ]
        return anchors unless system_role?(first)

        user_msg = messages[1..].find { |m| (m[:role] || m["role"]).to_s == "user" }
        anchors << user_msg if user_msg
        anchors
      end

      def system_role?(msg)
        return false if msg.nil?
        (msg[:role] || msg["role"]).to_s == "system"
      end
    end
  end
end
