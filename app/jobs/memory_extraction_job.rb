# frozen_string_literal: true

class MemoryExtractionJob < ApplicationJob
  queue_as :low

  EXTRACTION_PROMPT = <<~PROMPT.freeze
    Look at this single conversation exchange. Extract ONLY new, discrete facts worth remembering long-term.

    Return a JSON array. Each object has:
    - "content": A concise standalone statement
    - "type": "semantic" (fact), "preference" (user like/dislike/style), or "procedural" (how-to/command)
    - "importance": 0.0 to 1.0
    - "supersedes": If this corrects/updates old info, describe what it replaces (or null)

    Rules:
    - Only extract info worth remembering across sessions
    - Skip greetings, filler, acknowledgments
    - Preferences are high importance (0.7+)
    - Names, roles, locations are high importance (0.8+)
    - If nothing worth remembering, return []
    - Do NOT extract episodic summaries — just facts and preferences

    IMPORTANT: Return ONLY a raw JSON array. No explanation, no markdown, no text before or after.
    If nothing is worth remembering, return exactly: []
  PROMPT

  def perform(agent_id, user_message, assistant_response)
    agent = Agent.find_by(id: agent_id)
    return unless agent

    # Skip short/trivial exchanges
    return if user_message.length < 15 && assistant_response.length < 30

    memories = extract(agent:, user_message:, assistant_response:)
    return if memories.empty?

    memories.each do |mem|
      # Handle contradictions — if this supersedes old info, find and update it
      if mem["supersedes"].present?
        handle_supersede(agent:, new_content: mem["content"], supersedes: mem["supersedes"])
      end

      Memory::Store.call(
        agent: agent,
        content: mem["content"],
        memory_type: mem["type"],
        importance: mem["importance"].to_f.clamp(0.0, 1.0),
        metadata: { extracted_at: Time.current.iso8601, source: "auto_extraction" },
        async: true
      )
    end

    Rails.logger.info("[MemoryExtraction] Extracted #{memories.size} facts for agent #{agent.slug}")
  rescue StandardError => e
    Rails.logger.error("[MemoryExtraction] Failed for agent #{agent_id}: #{e.message}")
  end

  private

  def extract(agent:, user_message:, assistant_response:)
    resolver = Providers::Resolver.call(provider_name: agent.model_provider, agent: agent)
    return [] unless resolver.success?

    adapter = resolver.data[:adapter]

    exchange = "User: #{user_message.truncate(500)}\nAssistant: #{assistant_response.truncate(500)}"

    messages = [
      { role: "system", content: EXTRACTION_PROMPT },
      { role: "user", content: exchange }
    ]

    response = adapter.chat(messages: messages, options: { model: agent.llm_model })
    return [] unless response.success?

    content = response.data[:content].to_s.strip

    # Try to extract JSON array from response (LLM may include extra text)
    json_str = content.gsub(/\A```json?\s*/, "").gsub(/\s*```\z/, "")

    # If the response doesn't start with [, try to find the JSON array in the text
    unless json_str.start_with?("[")
      match = json_str.match(/\[.*\]/m)
      json_str = match[0] if match
    end

    # Empty array shortcut
    return [] if json_str.strip == "[]" || !json_str.include?("[")

    parsed = JSON.parse(json_str)

    return [] unless parsed.is_a?(Array)

    parsed.select do |entry|
      entry.is_a?(Hash) &&
        entry["content"].present? &&
        %w[semantic preference procedural].include?(entry["type"]) &&
        entry["importance"].is_a?(Numeric)
    end
  rescue JSON::ParserError => e
    Rails.logger.warn("[MemoryExtraction] JSON parse failed: #{e.message}")
    []
  end

  # Find and update memories that this new info contradicts
  def handle_supersede(agent:, new_content:, supersedes:)
    embedding = Memory::Embedding.generate(supersedes)
    return unless embedding

    # Find the old memory that's being corrected
    candidates = MemoryEntry.search_similar(embedding: embedding, agent: agent, limit: 3)
    match = candidates.find { |e| (1 - e.neighbor_distance) > 0.75 }

    if match
      Rails.logger.info("[MemoryExtraction] Superseding memory ##{match.id}: '#{match.content.truncate(50)}' → '#{new_content.truncate(50)}'")
      match.update!(
        content: new_content,
        metadata: match.metadata.merge(
          "superseded_at" => Time.current.iso8601,
          "previous_content" => match.content.truncate(200)
        )
      )
    end
  end
end
