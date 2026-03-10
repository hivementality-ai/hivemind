# frozen_string_literal: true

# Generates a short, descriptive title for a single-agent chat session.
# Triggered after the first meaningful exchange. Uses the cheapest available
# model to keep cost near zero. Guards atomically against overwriting
# user-set titles.
class SessionTitleJob < ApplicationJob
  queue_as :default

  MAX_TITLE_CHARS = 100
  MIN_TRANSCRIPT_SIZE = 2 # at least 1 user + 1 assistant message

  def perform(session_id)
    session = Session.find(session_id)
    agent   = session.agent

    return if title_already_set?(session)

    transcript = session.transcript || []
    return if transcript.size < MIN_TRANSCRIPT_SIZE

    resolver = Providers::Resolver.call(provider_name: agent.model_provider, agent:)
    return unless resolver.success?

    adapter      = resolver.data[:adapter]
    title_model  = cheapest_model(agent.model_provider)
    conversation = build_conversation_excerpt(transcript)

    result = adapter.chat(
      messages: [
        { role: "system", content: title_prompt },
        { role: "user",   content: conversation }
      ],
      options: { model: title_model, max_tokens: 30 }
    )

    return unless result.success?

    generated = result.data[:content].to_s.strip.gsub(/\A["']|["']\z/, "")
    return if generated.blank?

    generated = generated[0...MAX_TITLE_CHARS] if generated.length > MAX_TITLE_CHARS

    # Atomic update — only writes if title is still blank or "New Chat".
    # Closes the TOCTOU gap that a reload-and-check would leave open.
    updated = Session.where(id: session.id, title: [ nil, "", "New Chat" ])
                     .update_all(title: generated)

    if updated > 0
      track_usage(agent:, session:, model: title_model, usage: result.data[:usage])
      ActionCable.server.broadcast("session_#{session.id}", { type: "title_update", title: generated })
      Rails.logger.info("[SessionTitleJob] Session #{session_id}: titled \"#{generated}\"")
    end
  rescue StandardError => e
    Rails.logger.warn("[SessionTitleJob] Failed for session #{session_id}: #{e.message}")
  end

  private

  def title_already_set?(session)
    title = session.title.to_s.strip
    title.present? && title != "New Chat"
  end

  def build_conversation_excerpt(transcript)
    # Use the first 4 messages for context — enough to infer the topic cheaply.
    transcript.first(4).map do |msg|
      role    = msg["role"] == "user" ? "User" : "Assistant"
      content = msg["content"].to_s.truncate(300)
      "#{role}: #{content}"
    end.join("\n")
  end

  def title_prompt
    "Generate a concise 3-8 word title for this conversation. " \
    "No quotes, no punctuation at the end, no meta-commentary. " \
    "Just the title."
  end

  def cheapest_model(provider)
    case provider
    when "anthropic" then "claude-haiku-4-5"
    when "openai"    then "gpt-5.2-nano"
    else                  "claude-haiku-4-5"
    end
  end

  def track_usage(agent:, session:, model:, usage:)
    return if usage.blank?

    input_tokens  = usage[:input_tokens]  || 0
    output_tokens = usage[:output_tokens] || 0
    return if input_tokens == 0 && output_tokens == 0

    UsageRecord.create(
      agent:,
      session:,
      provider:       agent.model_provider,
      llm_model:      model,
      input_tokens:,
      output_tokens:,
      cost_cents:     CostEstimator.estimate(model:, input_tokens:, output_tokens:)
    )
  rescue StandardError => e
    Rails.logger.warn("[SessionTitleJob] Usage tracking failed: #{e.message}")
  end
end
