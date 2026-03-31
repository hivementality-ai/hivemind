# frozen_string_literal: true

class SessionArchivalJob < ApplicationJob
  queue_as :low

  # Archive sessions inactive for more than 7 days.
  # Before archiving, consolidates the transcript into long-term memories
  # so agents retain important context even after the transcript is cleared.
  INACTIVE_THRESHOLD = 7.days

  ARCHIVAL_PROMPT = <<~PROMPT.freeze
    You are reviewing a full conversation transcript that is about to be archived and permanently deleted.
    Your job is to extract everything worth remembering AND flag anything that contradicts or updates the agent's existing memories.

    Return a JSON array. Each object has:
    - "content": A concise standalone statement (one fact/preference/lesson per entry)
    - "type": One of "semantic" (facts/knowledge), "preference" (user likes/dislikes/style), "procedural" (how-to/commands/workflows), or "episodic" (event summary)
    - "importance": A float from 0.0 to 1.0
    - "supersedes": If this corrects, updates, or replaces older info, describe what it replaces (e.g., "User's preferred language was Python" if they now prefer Ruby). null if not applicable.

    Guidelines:
    - This is the LAST CHANCE to save information from this conversation — be thorough
    - Preferences are critical (0.8+) — they affect every future interaction
    - Procedural knowledge (deploy steps, project setup) is high importance (0.7-0.9)
    - Project decisions, deadlines, and outcomes are important (0.6-0.8)
    - Names, roles, relationships are high importance (0.8+)
    - Skip greetings, filler, and acknowledgments
    - Write each memory as if explaining to someone with zero context
    - If nothing important was discussed, return []

    Return ONLY the raw JSON array. No markdown, no explanation.
  PROMPT

  def perform
    sessions = Session.where(status: :active)
                      .where("last_activity_at < ?", INACTIVE_THRESHOLD.ago)
                      .includes(:agent)

    archived_count = 0

    sessions.find_each do |session|
      next if session.transcript.blank?

      # Consolidate memories before archiving
      consolidate_memories(session) if session.transcript.size >= 4

      # Archive the transcript
      session.transcript_archives.create!(
        content: session.transcript,
        archived_at: Time.current
      )

      session.update!(
        status: :archived,
        transcript: []
      )

      archived_count += 1
    rescue StandardError => e
      Rails.logger.error("[SessionArchivalJob] Failed to archive session #{session.id}: #{e.message}")
    end

    Rails.logger.info("[SessionArchivalJob] Archived #{archived_count} sessions")
  end

  private

  def consolidate_memories(session)
    agent = session.agent
    return unless agent

    conversation = session.transcript.map do |msg|
      role = msg["role"]&.capitalize || "Unknown"
      "#{role}: #{msg["content"].to_s.truncate(1000)}"
    end.join("\n\n")

    memories = extract_memories(agent: agent, conversation: conversation)
    return if memories.empty?

    memories.each do |mem|
      # Handle supersession — find and update contradicted memories
      if mem["supersedes"].present?
        handle_supersede(agent: agent, new_content: mem["content"], supersedes: mem["supersedes"])
      end

      Memory::Store.call(
        agent: agent,
        content: mem["content"],
        source: session,
        memory_type: mem["type"],
        importance: mem["importance"].to_f.clamp(0.0, 1.0),
        metadata: {
          source: "archival_consolidation",
          session_id: session.id,
          archived_at: Time.current.iso8601
        },
        async: true
      )
    end

    Rails.logger.info("[SessionArchivalJob] Consolidated #{memories.size} memories from session #{session.id}")
  rescue StandardError => e
    Rails.logger.warn("[SessionArchivalJob] Memory consolidation failed for session #{session.id}: #{e.message}")
    # Don't block archival if memory extraction fails
  end

  def extract_memories(agent:, conversation:)
    resolver = Providers::Resolver.call(provider_name: agent.model_provider, agent: agent)
    return [] unless resolver.success?

    adapter = resolver.data[:adapter]

    messages = [
      { role: "system", content: ARCHIVAL_PROMPT },
      { role: "user", content: conversation.truncate(12_000) }
    ]

    response = adapter.chat(messages: messages, options: { model: agent.llm_model })
    return [] unless response.success?

    content = response.data[:content].to_s.strip
    json_str = content.gsub(/\A```json?\s*/, "").gsub(/\s*```\z/, "")

    unless json_str.start_with?("[")
      match = json_str.match(/\[.*\]/m)
      json_str = match[0] if match
    end

    return [] if json_str.strip == "[]" || !json_str.include?("[")

    parsed = JSON.parse(json_str)
    return [] unless parsed.is_a?(Array)

    parsed.select do |entry|
      entry.is_a?(Hash) &&
        entry["content"].present? &&
        %w[semantic preference procedural episodic].include?(entry["type"]) &&
        entry["importance"].is_a?(Numeric)
    end
  rescue JSON::ParserError => e
    Rails.logger.warn("[SessionArchivalJob] JSON parse failed: #{e.message}")
    []
  end

  def handle_supersede(agent:, new_content:, supersedes:)
    embedding = Memory::Embedding.generate(supersedes)
    return unless embedding

    candidates = MemoryEntry.search_similar(embedding: embedding, agent: agent, limit: 3)
    match = candidates.find { |e| (1 - e.neighbor_distance) > 0.75 }

    if match
      Rails.logger.info("[SessionArchivalJob] Superseding memory ##{match.id}: '#{match.content.truncate(50)}' → '#{new_content.truncate(50)}'")
      match.update!(
        content: new_content,
        metadata: match.metadata.merge(
          "superseded_at" => Time.current.iso8601,
          "previous_content" => match.content.truncate(200)
        )
      )
    end
  rescue StandardError => e
    Rails.logger.warn("[SessionArchivalJob] Supersession failed: #{e.message}")
  end
end
