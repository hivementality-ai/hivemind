# frozen_string_literal: true

class MemoryConsolidationJob < ApplicationJob
  queue_as :low

  # Names the agent so the extractor doesn't misread "User: hey <agent name>"
  # as the user's own name — see MemoryExtractionJob.extraction_prompt.
  def self.extraction_prompt(agent_name)
    <<~PROMPT
      Analyze the following conversation between a human ("User") and an AI agent named #{agent_name} ("Assistant") and extract important information. Return a JSON array of memory objects.

      Each memory object should have:
      - "content": A concise, standalone statement (one fact/preference/lesson per entry)
      - "type": One of "semantic" (facts/knowledge), "preference" (user likes/dislikes/style), "procedural" (how-to/commands/workflows), or "episodic" (event summary)
      - "importance": A float from 0.0 to 1.0 (1.0 = critical to remember, 0.5 = nice to know, 0.1 = trivial)

      Guidelines:
      - Extract discrete facts, not vague summaries
      - Preferences are high importance (0.7-1.0) — they affect every future interaction
      - Procedural knowledge (commands, deploy steps) is high importance (0.7-0.9)
      - Casual chitchat or greetings get low importance (0.1-0.3)
      - When the user addresses someone by name (e.g. "hey #{agent_name}"), they are addressing the agent — that is #{agent_name}'s name, NOT the user's name. Never infer the user's own name or nickname from how they address the agent; only record it if the user states it about themselves ("my name is...", "I'm...").
      - If nothing important was discussed, return an empty array []
      - Write each memory as if explaining to someone with no context

      Example output:
      [
        {"content": "User introduced themselves as Alex and prefers to be called Al", "type": "semantic", "importance": 0.9},
        {"content": "User prefers dark mode and minimalist UI designs", "type": "preference", "importance": 0.8},
        {"content": "To deploy: run docker compose up -d then check /health", "type": "procedural", "importance": 0.7},
        {"content": "Discussed project timeline on Feb 23 — aiming for March launch", "type": "episodic", "importance": 0.5}
      ]

      Return ONLY the JSON array, no other text.
    PROMPT
  end

  # Consolidate a session's conversation into typed memory entries
  def perform(session_id)
    session = Session.find_by(id: session_id)
    return unless session

    agent = session.agent
    return unless agent

    transcript = session.transcript
    return if transcript.blank? || transcript.size < 4 # Skip very short conversations

    # Build conversation text from transcript
    conversation = transcript.map do |msg|
      role = msg["role"]&.capitalize || "Unknown"
      "#{role}: #{msg["content"].to_s.truncate(1000)}"
    end.join("\n\n")

    # Use the agent's LLM to extract memories
    memories = extract_memories(agent:, conversation:)
    return if memories.empty?

    # Store each extracted memory
    memories.each do |mem|
      Memory::Store.call(
        agent: agent,
        content: mem["content"],
        source: session,
        memory_type: mem["type"],
        importance: mem["importance"].to_f.clamp(0.0, 1.0),
        metadata: { consolidated_from: session.id, consolidated_at: Time.current.iso8601 },
        async: true
      )
    end

    # Mark raw episodic entries from this session as consolidated
    MemoryEntry.where(agent: agent, source: session, memory_type: "episodic", consolidated: false)
               .update_all(consolidated: true)

    Rails.logger.info("[MemoryConsolidation] Extracted #{memories.size} memories from session #{session_id}")
  rescue StandardError => e
    Rails.logger.error("[MemoryConsolidation] Failed for session #{session_id}: #{e.message}")
  end

  private

  def extract_memories(agent:, conversation:)
    resolver = Providers::Resolver.call(provider_name: agent.model_provider, agent: agent)
    return [] unless resolver.success?

    adapter = resolver.data[:adapter]

    messages = [
      { role: "system", content: self.class.extraction_prompt(agent.name) },
      { role: "user", content: conversation.truncate(8000) }
    ]

    response = adapter.chat(messages: messages, options: { model: agent.llm_model })
    return [] unless response.success?

    content = response.data[:content].to_s.strip

    # Parse JSON from response (handle markdown code blocks)
    json_str = content.gsub(/\A```json?\s*/, "").gsub(/\s*```\z/, "")
    parsed = JSON.parse(json_str)

    return [] unless parsed.is_a?(Array)

    # Validate each entry
    parsed.select do |entry|
      entry.is_a?(Hash) &&
        entry["content"].present? &&
        %w[semantic preference procedural episodic].include?(entry["type"]) &&
        entry["importance"].is_a?(Numeric)
    end
  rescue JSON::ParserError => e
    Rails.logger.warn("[MemoryConsolidation] JSON parse failed: #{e.message}")
    []
  end
end
