# frozen_string_literal: true

# Generates a short, descriptive title for a single-agent chat session.
# Triggered after the first meaningful exchange. Uses the cheapest available
# model to keep cost near zero. Guards atomically against overwriting
# user-set titles.
class SessionTitleJob < ApplicationJob
  queue_as :low

  MAX_TITLE_CHARS = 100
  MIN_TRANSCRIPT_SIZE = 2 # at least 1 user + 1 assistant message

  def perform(session_id)
    session = Session.find(session_id)
    agent   = session.agent

    return if title_already_set?(session)

    transcript = session.transcript || []
    return if transcript.size < MIN_TRANSCRIPT_SIZE

    adapter, title_model = resolve_cheap_provider(agent)
    return unless adapter

    conversation = build_conversation_excerpt(transcript)

    result = adapter.chat(
      messages: [
        { role: "system", content: title_prompt },
        { role: "user",   content: TitleSanitizer.request(conversation) }
      ],
      options: { model: title_model, max_tokens: 30 }
    )

    return unless result.success?

    generated = result.data[:content].to_s.strip.gsub(/\A["']|["']\z/, "")
    return if generated.blank? || TitleSanitizer.refusal?(generated)

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

  # Use the cheapest available provider — don't route through SDK proxy for housekeeping
  def resolve_cheap_provider(agent)
    # Try Anthropic with Haiku (API key path, not OAuth)
    anthropic = ProviderConfig.find_by(adapter_type: "anthropic", enabled: true)
    if anthropic
      resolver = Providers::Resolver.call(provider_name: "anthropic")
      if resolver.success?
        # Check it's not an OAuth token (which would go through SDK proxy)
        key = anthropic.api_key
        unless key&.start_with?("sk-ant-oat")
          return [ resolver.data[:adapter], LlmModelRegistry::Anthropic::DEFAULT_SUMMARIZER ]
        end
      end
    end

    # Try OpenAI
    openai = ProviderConfig.find_by(adapter_type: "openai", enabled: true)
    if openai
      resolver = Providers::Resolver.call(provider_name: "openai")
      return [ resolver.data[:adapter], LlmModelRegistry::OpenAI::DEFAULT_SUMMARIZER ] if resolver.success?
    end

    # Try Ollama
    ollama = ProviderConfig.find_by(adapter_type: "ollama", enabled: true)
    if ollama
      resolver = Providers::Resolver.call(provider_name: "ollama")
      return [ resolver.data[:adapter], "llama3.2:3b" ] if resolver.success?
    end

    # Last resort: agent's own provider (may be OAuth, but better than nothing)
    resolver = Providers::Resolver.call(provider_name: agent.model_provider, agent: agent)
    if resolver.success?
      cheap =
        case agent.model_provider
        when "anthropic" then LlmModelRegistry::Anthropic::DEFAULT_SUMMARIZER
        when "openai"    then LlmModelRegistry::OpenAI::DEFAULT_SUMMARIZER
        else agent.llm_model
        end
      return [ resolver.data[:adapter], cheap ]
    end

    [ nil, nil ]
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
