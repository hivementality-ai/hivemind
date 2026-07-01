# frozen_string_literal: true

# Summarizes older transcript messages into a compact rolling summary.
# Keeps last N messages raw and compresses everything else into ~200 tokens.
# Triggered after every SUMMARIZE_EVERY turns in ChatStreamJob.
class ConversationSummaryJob < ApplicationJob
  queue_as :low

  KEEP_RAW = 4          # Keep last 4 messages (2 user + 2 assistant turns) raw
  MAX_SUMMARY_CHARS = 800 # Target ~200 tokens for the summary

  def perform(session_id)
    session = Session.find(session_id)
    agent = session.agent
    transcript = session.transcript || []

    return if transcript.size <= KEEP_RAW

    # Only summarize messages we haven't already summarized
    summarized_through = session.summary_through_index || 0
    messages_to_summarize = transcript[summarized_through..(-KEEP_RAW - 1)]

    return if messages_to_summarize.blank?

    # Build the text to summarize
    existing_summary = session.conversation_summary
    text_to_summarize = build_summarization_input(existing_summary, messages_to_summarize)

    # Use the agent's own provider to generate the summary
    resolver = Providers::Resolver.call(provider_name: agent.model_provider, agent:)
    return unless resolver.success?

    adapter = resolver.data[:adapter]

    # Use the cheapest available model for summarization
    summary_model = cheapest_model(agent.model_provider)

    result = adapter.chat(
      messages: [
        { role: "system", content: summarization_prompt },
        { role: "user", content: text_to_summarize }
      ],
      options: { model: summary_model, max_tokens: 300 }
    )

    return unless result.success?

    summary = result.data[:content].to_s.strip
    return if summary.blank?

    # Truncate if the model got verbose
    summary = summary[0...MAX_SUMMARY_CHARS] if summary.length > MAX_SUMMARY_CHARS

    # Update session with new summary
    new_through_index = transcript.size - KEEP_RAW
    session.update!(
      conversation_summary: summary,
      summary_through_index: new_through_index
    )

    # Track the summarization usage
    usage = result.data[:usage] || {}
    input_tokens = usage[:input_tokens] || 0
    output_tokens = usage[:output_tokens] || 0
    if input_tokens > 0 || output_tokens > 0
      UsageRecord.create(
        agent:,
        session:,
        provider: agent.model_provider,
        llm_model: summary_model,
        input_tokens:,
        output_tokens:,
        cost_cents: CostEstimator.estimate(model: summary_model, input_tokens:, output_tokens:)
      )
    end

    Rails.logger.info("[ConversationSummaryJob] Session #{session_id}: summarized #{messages_to_summarize.size} messages (through index #{new_through_index})")
  rescue StandardError => e
    Rails.logger.warn("[ConversationSummaryJob] Failed for session #{session_id}: #{e.message}")
  end

  private

  def summarization_prompt
    <<~PROMPT.strip
      You are a conversation summarizer. Produce a brief, dense summary of the conversation below.
      Focus on: decisions made, tasks discussed, key information exchanged, and current state.
      Skip: greetings, small talk, filler.
      Keep it under 200 words. Write in past tense, third person ("The user asked...", "The agent built...").
      If a previous summary is provided, incorporate and update it — don't just append.
    PROMPT
  end

  def build_summarization_input(existing_summary, messages)
    parts = []

    if existing_summary.present?
      parts << "Previous summary:\n#{existing_summary}\n"
    end

    parts << "New messages to incorporate:"
    messages.each do |msg|
      role = msg["role"] == "user" ? "User" : "Agent"
      content = msg["content"].to_s.truncate(500)
      parts << "#{role}: #{content}"
    end

    parts.join("\n")
  end

  def cheapest_model(provider)
    case provider
    when "anthropic" then LlmModelRegistry::Anthropic::DEFAULT_SUMMARIZER
    when "openai"    then LlmModelRegistry::OpenAI::DEFAULT_SUMMARIZER
    else                  LlmModelRegistry::Anthropic::DEFAULT_SUMMARIZER
    end
  end
end
