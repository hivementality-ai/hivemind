# frozen_string_literal: true

module Agents
  # User-triggered compaction (via the /compact hashtag action in a later PR).
  # Identical to AutoCompact but accepts an optional focus prompt that
  # steers what gets preserved. Ports rubyn-code's context/manual_compact.rb.
  module ManualCompact
    BASE_INSTRUCTION = AutoCompact::SUMMARY_INSTRUCTION

    # @param messages [Array<Hash>] current conversation messages
    # @param agent [Agent] the agent whose session is being compacted
    # @param focus [String, nil] optional user-supplied focus prompt
    # @return [Array<Hash>, nil] compacted single-message array, or nil on failure
    def self.call(messages, agent:, focus: nil)
      client = AutoCompact.haiku_client(agent: agent)
      return nil unless client

      transcript_text = AutoCompact.serialize_tail(messages, AutoCompact::MAX_TRANSCRIPT_CHARS)
      instruction = build_instruction(focus)
      summary = request_summary(transcript_text, instruction, client)
      return nil if summary.blank?

      [ { "role" => "user", "content" => "[Context compacted — manual]\n\n#{summary}" } ]
    rescue StandardError => e
      Rails.logger.error("[ManualCompact] Failed: #{e.class}: #{e.message}")
      nil
    end

    def self.build_instruction(focus)
      return BASE_INSTRUCTION if focus.nil? || focus.strip.empty?

      "#{BASE_INSTRUCTION}\nAdditional focus: #{focus}"
    end
    private_class_method :build_instruction

    def self.request_summary(transcript_text, instruction, client)
      response = client.chat(
        messages: [
          { role: "user", content: "#{instruction}\n\n---\n\n#{transcript_text}" }
        ],
        options: { model: AutoCompact::SUMMARIZATION_MODEL, max_tokens: AutoCompact::SUMMARIZATION_MAX_TOKENS }
      )
      return nil unless response&.success?

      response.data[:content].to_s
    end
    private_class_method :request_summary
  end
end
