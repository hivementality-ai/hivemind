# frozen_string_literal: true

# Generates a short, descriptive title for a team chat session.
# Triggered after the first full agent response round. Reads from the
# team_chat_messages relation (unlike SessionTitleJob, which reads JSONB).
# Guards atomically against overwriting user-set titles.
class TeamChatTitleJob < ApplicationJob
  queue_as :low

  MAX_TITLE_CHARS  = 100
  MIN_MESSAGE_COUNT = 2 # at least 1 user message + 1 agent response

  def perform(team_chat_session_id)
    session = TeamChatSession.find(team_chat_session_id)

    return if title_already_set?(session)

    messages = session.team_chat_messages.order(:created_at).limit(6).to_a
    return if messages.size < MIN_MESSAGE_COUNT

    # Use the team's first enabled agent for the LLM call.
    agent = session.team.agents.enabled.order(:name).first
    return unless agent

    resolver = Providers::Resolver.call(provider_name: agent.model_provider, agent:)
    return unless resolver.success?

    adapter     = resolver.data[:adapter]
    title_model = cheapest_model(agent.model_provider)
    conversation = build_conversation_excerpt(messages)

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
    updated = TeamChatSession.where(id: session.id, title: [ nil, "", "New Chat" ])
                             .update_all(title: generated)

    if updated > 0
      track_usage(agent:, session:, model: title_model, usage: result.data[:usage])
      ActionCable.server.broadcast("team_chat_#{session.id}", { type: "title_update", title: generated })
      Rails.logger.info("[TeamChatTitleJob] Session #{team_chat_session_id}: titled \"#{generated}\"")
    end
  rescue StandardError => e
    Rails.logger.warn("[TeamChatTitleJob] Failed for session #{team_chat_session_id}: #{e.message}")
  end

  private

  def title_already_set?(session)
    title = session.title.to_s.strip
    title.present? && title != "New Chat"
  end

  def build_conversation_excerpt(messages)
    messages.map do |msg|
      if msg.from_user?
        "User: #{msg.content.to_s.truncate(300)}"
      else
        agent_sender = Agent.find_by(id: msg.sender_id)
        label = agent_sender&.name || "Agent"
        "#{label}: #{msg.content.to_s.truncate(300)}"
      end
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
    when "openai"    then "gpt-5.4-nano"
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
    Rails.logger.warn("[TeamChatTitleJob] Usage tracking failed: #{e.message}")
  end
end
