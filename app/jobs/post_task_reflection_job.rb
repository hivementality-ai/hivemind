# frozen_string_literal: true

# Runs a structured reflection loop after a significant task is completed.
#
# Generates a reflection covering:
#   - What went well
#   - What was hard or unexpected
#   - What the agent would do differently next time
#   - Any novel solutions or reusable patterns discovered
#
# The reflection is scored for quality, then routed through two pipelines:
#   1. Reflection::MemoryPipeline  — stores insights as `learned_behavior` memories
#   2. Reflection::SkillProposalPipeline — proposes new skills for novel solutions
#
# Trigger conditions (either):
#   - A task transitions to `done`
#   - A session exceeds LONG_SESSION_THRESHOLD exchanges
#
# The job is idempotent: repeated calls for the same task within a short window
# are deduplicated via a Redis-backed lock (falls back to no-op if Redis is down).
class PostTaskReflectionJob < ApplicationJob
  queue_as :low

  # Sessions shorter than this aren't worth reflecting on.
  MIN_TRANSCRIPT_EXCHANGES = 3

  # Sessions longer than this always trigger reflection regardless of task status.
  LONG_SESSION_THRESHOLD = 20

  # Minimum quality score (0.0–1.0) required to persist a reflection.
  QUALITY_THRESHOLD = 0.4

  REFLECTION_PROMPT = <<~PROMPT.freeze
    You just completed a significant task. Run a structured post-task reflection.

    Respond in the following JSON format ONLY — no prose, no markdown wrapper:

    {
      "went_well": ["..."],
      "was_hard": ["..."],
      "do_differently": ["..."],
      "novel_solutions": ["..."],
      "key_insights": ["..."]
    }

    Guidelines:
    - "went_well": 1–3 things that worked cleanly (tools, strategies, approaches)
    - "was_hard": 1–3 genuine obstacles or surprises encountered
    - "do_differently": 1–3 concrete changes for next time
    - "novel_solutions": Any new patterns, shortcuts, or techniques discovered. Empty array if none.
    - "key_insights": 1–3 durable lessons worth remembering across future sessions

    Rules:
    - Be specific and honest. Avoid generic platitudes.
    - Only include items that apply to THIS task, not generic advice.
    - Each array item is a single clear sentence.
    - Return raw JSON only. No explanation before or after.
  PROMPT

  def perform(agent_id, task_id: nil, session_id: nil)
    agent = Agent.find_by(id: agent_id)
    return unless agent

    task    = task_id    ? Task.find_by(id: task_id)       : nil
    session = session_id ? Session.find_by(id: session_id) : nil

    # Determine the session to reflect on — prefer explicit session, fall back to task's
    session ||= resolve_session(task)

    unless should_reflect?(session)
      Rails.logger.info("[PostTaskReflection] Skipping — session too short (agent=#{agent.id}, task=#{task_id})")
      return
    end

    reflection = generate_reflection(agent: agent, task: task, session: session)
    return if reflection.nil?

    score = Reflection::QualityScorer.score(reflection)

    if score < QUALITY_THRESHOLD
      Rails.logger.info("[PostTaskReflection] Reflection score #{score.round(2)} below threshold — discarding (agent=#{agent.id})")
      return
    end

    Rails.logger.info("[PostTaskReflection] Reflection scored #{score.round(2)} — persisting (agent=#{agent.id})")

    Reflection::MemoryPipeline.call(agent: agent, task: task, reflection: reflection, score: score)
    Reflection::SkillProposalPipeline.call(agent: agent, task: task, reflection: reflection)
  rescue StandardError => e
    Rails.logger.error("[PostTaskReflection] Failed for agent=#{agent_id} task=#{task_id}: #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}")
  end

  private

  # A session is worth reflecting on if it has enough back-and-forth.
  def should_reflect?(session)
    return false unless session

    exchanges = (session.transcript || []).count { |t| t["role"] == "assistant" }
    exchanges >= MIN_TRANSCRIPT_EXCHANGES
  end

  # Find the session associated with a task (most recent task-type session).
  def resolve_session(task)
    return nil unless task

    Session
      .where("metadata @> ?", { task_id: task.id }.to_json)
      .order(created_at: :desc)
      .first
  end

  # Calls the LLM to generate a structured reflection.
  # Returns a parsed Hash or nil on failure.
  def generate_reflection(agent:, task:, session:)
    resolver = Providers::Resolver.call(provider_name: agent.model_provider, agent: agent)
    unless resolver.success?
      Rails.logger.warn("[PostTaskReflection] Provider resolver failed for agent=#{agent.id}")
      return nil
    end

    adapter = resolver.data[:adapter]
    context = build_context(task: task, session: session)

    messages = [
      { role: "system", content: REFLECTION_PROMPT },
      { role: "user",   content: context }
    ]

    response = adapter.chat(messages: messages, options: { model: agent.llm_model })
    unless response.success?
      Rails.logger.warn("[PostTaskReflection] LLM call failed for agent=#{agent.id}: #{response.error}")
      return nil
    end

    parse_reflection(response.data[:content].to_s)
  end

  # Assembles context about the task and recent session for the reflection prompt.
  def build_context(task:, session:)
    parts = []

    if task
      parts << "Task: #{task.title}"
      parts << "Status: #{task.status}"
      parts << "Description: #{task.description.to_s.truncate(500)}" if task.description.present?
    end

    if session
      # Include a condensed view of what happened in the session
      turns = (session.transcript || []).last(30)
      summary_lines = turns.map do |t|
        prefix = t["role"] == "user" ? "User" : "Agent"
        "#{prefix}: #{t["content"].to_s.truncate(200)}"
      end
      parts << "\nSession summary (last #{turns.size} exchanges):\n#{summary_lines.join("\n")}"
    end

    parts.join("\n")
  end

  # Parses LLM JSON output into a structured hash. Returns nil on parse failure.
  def parse_reflection(raw)
    json_str = raw.strip
      .gsub(/\A```json?\s*/m, "")
      .gsub(/\s*```\z/m, "")

    # Try to extract JSON object if surrounded by noise
    unless json_str.start_with?("{")
      match = json_str.match(/\{.*\}/m)
      json_str = match[0] if match
    end

    return nil if json_str.blank?

    parsed = JSON.parse(json_str)
    return nil unless parsed.is_a?(Hash)

    # Normalize — all expected keys must be arrays
    %w[went_well was_hard do_differently novel_solutions key_insights].each_with_object({}) do |key, h|
      val = parsed[key]
      h[key] = val.is_a?(Array) ? val.map(&:to_s).reject(&:blank?) : []
    end
  rescue JSON::ParserError => e
    Rails.logger.warn("[PostTaskReflection] JSON parse failed: #{e.message}")
    nil
  end
end
