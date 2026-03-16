# frozen_string_literal: true

module Memory
  class Summarizer
    LINE_BUDGET = 180

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are a memory curator for an AI agent. Your job is to take a collection of raw memory entries and produce a clean, consolidated MEMORY.md file that the agent will read at the start of every conversation.

      Rules:
      - **Deduplicate** — if multiple entries say the same thing, keep one clean version
      - **Resolve contradictions** — if an old entry says one thing and a newer one says another, keep only the current truth
      - **Prioritize** — user preferences and identity facts first, then procedural knowledge, then general context. Drop trivia.
      - **One thought per line** — each bullet should be self-contained and make sense on its own
      - **Stay under #{LINE_BUDGET} lines** including headers
      - **Use the agent's voice** — this is the agent's memory about its user and its work, written naturally
      - **Drop low-value content** — greetings, small talk, anything that wouldn't help the agent do its job better
      - **Preserve #remember entries exactly** — anything the user explicitly asked to remember is highest priority and should not be reworded or dropped

      Output format — produce ONLY the markdown content, no explanation:

      # {Agent Name} — Memory

      ## User Preferences
      - preference 1
      - preference 2

      ## Key Knowledge
      - fact 1
      - fact 2

      ## Procedures
      - how-to 1

      ## Recent Context
      - recent relevant fact
    PROMPT

    def self.call(agent:)
      new(agent: agent).call
    end

    def initialize(agent:)
      @agent = agent
    end

    def call
      raw_content = build_raw_content
      return nil if raw_content.blank?

      summarized = run_llm(raw_content)
      return nil unless summarized

      # Enforce line budget
      lines = summarized.lines.first(LINE_BUDGET)
      lines.join
    rescue StandardError => e
      Rails.logger.error("[Memory::Summarizer] Failed for agent #{@agent.id}: #{e.message}")
      nil
    end

    private

    def build_raw_content
      sections = []

      # Explicit #remember entries (highest priority — marked by hashtag action)
      remembers = MemoryEntry.where(agent: @agent)
                             .where("metadata->>'source' = ?", "hashtag_action")
                             .order(created_at: :desc)
                             .limit(30)
      if remembers.any?
        sections << "## Explicit #remember entries (DO NOT drop or reword these)"
        remembers.each { |r| sections << "- #{r.content}" }
        sections << ""
      end

      # Preferences
      prefs = MemoryEntry.where(agent: @agent).preferences.by_importance.limit(20)
      if prefs.any?
        sections << "## Preferences"
        prefs.each { |p| sections << "- #{p.content}" }
        sections << ""
      end

      # Semantic facts
      facts = MemoryEntry.where(agent: @agent, memory_type: "semantic")
                         .order(importance: :desc, created_at: :desc)
                         .limit(30)
      if facts.any?
        sections << "## Facts"
        facts.each { |f| sections << "- #{f.content}" }
        sections << ""
      end

      # Procedural
      procedures = MemoryEntry.where(agent: @agent, memory_type: "procedural")
                              .order(importance: :desc)
                              .limit(15)
      if procedures.any?
        sections << "## Procedures"
        procedures.each { |p| sections << "- #{p.content}" }
      end

      sections.join("\n")
    end

    def run_llm(raw_content)
      resolver = Providers::Resolver.call(provider_name: "anthropic", agent: @agent)
      return nil unless resolver.success?

      adapter = resolver.data[:adapter]

      messages = [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: "Agent name: #{@agent.name}\nRole: #{@agent.role}\n\nRaw memories to consolidate:\n\n#{raw_content}" }
      ]

      result = adapter.chat(messages: messages, options: { model: "claude-haiku-4-5", max_tokens: 4096 })
      return nil unless result.success?

      content = result.data[:content].to_s.strip
      # Strip any markdown code fences the model might wrap it in
      content.gsub(/\A```markdown?\s*\n?/, "").gsub(/\n?```\z/, "")
    end
  end
end
