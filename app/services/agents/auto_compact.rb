# frozen_string_literal: true

module Agents
  # LLM-driven summarization triggered when the context budget is about to
  # blow. Ports rubyn-code's context/auto_compact.rb.
  #
  # Serializes the conversation tail, asks Claude Haiku to produce a
  # continuity summary, and returns a fresh single-message conversation
  # that drops into the agent loop as `[Context compacted]\n\n<summary>`.
  # The DB-persisted transcript (Session#transcript) is untouched — this
  # only reshapes the in-memory message list handed to the LLM on the
  # next turn.
  module AutoCompact
    SUMMARY_INSTRUCTION = <<~PROMPT
      You are a context compaction assistant. Summarize the following conversation transcript for continuity. Cover exactly three areas:

      1) **What was accomplished** - completed tasks, files changed, problems solved
      2) **Current state** - what the user/agent is working on right now, any pending actions
      3) **Key decisions made** - architectural choices, user preferences, constraints established

      Be concise but preserve all details needed to continue the work seamlessly. Use bullet points.
    PROMPT

    MAX_TRANSCRIPT_CHARS = 80_000
    SUMMARIZATION_MODEL = LlmModelRegistry::Anthropic::DEFAULT_SUMMARIZER
    SUMMARIZATION_MAX_TOKENS = 2048

    # @param messages [Array<Hash>] current conversation messages
    # @param agent [Agent] the agent whose session is being compacted
    # @return [Array<Hash>, nil] compacted single-message array, or nil on failure
    def self.call(messages, agent:)
      client = haiku_client(agent: agent)
      return nil unless client

      transcript_text = serialize_tail(messages, MAX_TRANSCRIPT_CHARS)
      summary = request_summary(transcript_text, client)
      return nil if summary.blank?

      [ { "role" => "user", "content" => "[Context compacted]\n\n#{summary}" } ]
    rescue StandardError => e
      Rails.logger.error("[AutoCompact] Failed: #{e.class}: #{e.message}")
      nil
    end

    # Build a dedicated Anthropic adapter pinned to Haiku so summarization
    # stays cheap regardless of the agent's own model. Returns nil when
    # no Anthropic provider is configured or no key is available.
    def self.haiku_client(agent:)
      config = ProviderConfig.enabled_providers.find_by(adapter_type: "anthropic")
      return nil unless config

      api_key = config.api_key(agent: agent)
      return nil if api_key.blank?

      Providers::AnthropicAdapter.new(config: config, api_key: api_key)
    end

    def self.serialize_tail(messages, max_chars)
      json = JSON.generate(messages)
      return json if json.length <= max_chars
      json[-max_chars..]
    end

    def self.request_summary(transcript_text, client)
      response = client.chat(
        messages: [
          { role: "user", content: "#{SUMMARY_INSTRUCTION}\n\n---\n\n#{transcript_text}" }
        ],
        options: { model: SUMMARIZATION_MODEL, max_tokens: SUMMARIZATION_MAX_TOKENS }
      )
      return nil unless response&.success?

      response.data[:content].to_s
    end
  end
end
