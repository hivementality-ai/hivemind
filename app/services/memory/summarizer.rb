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

      CRITICAL: Output ONLY the markdown file content. No preamble, no explanation, no summary of what you did, no "Here's the output" or "Consolidation Summary" sections. Start directly with the # heading and end with the last bullet point. Nothing else.

      Output format:

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
      # Use the cheapest available provider — don't bill the agent's own model for housekeeping
      adapter, model = resolve_cheap_provider
      return nil unless adapter

      messages = [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: "Agent name: #{@agent.name}\nRole: #{@agent.role}\n\nRaw memories to consolidate:\n\n#{raw_content}" }
      ]

      result = adapter.chat(messages: messages, options: { model: model, max_tokens: 4096 })
      return nil unless result.success?

      content = result.data[:content].to_s.strip
      # Strip markdown code fences
      content = content.gsub(/\A```markdown?\s*\n?/, "").gsub(/\n?```\z/, "")
      # Strip any preamble before the first heading
      content = content.sub(/\A.*?(?=^#\s)/m, "")
      # Strip any postamble after the last bullet or heading (consolidation summaries, explanations)
      content = content.sub(/\n---\n.*/m, "")
      content.strip
    end

    # Find the cheapest available provider for background work.
    # Priority: Anthropic Haiku > OpenAI Nano > Ollama > agent's own provider
    def resolve_cheap_provider
      # Try Anthropic with Haiku
      anthropic = ProviderConfig.find_by(adapter_type: "anthropic", enabled: true)
      if anthropic
        resolver = Providers::Resolver.call(provider_name: "anthropic")
        return [ resolver.data[:adapter], LlmModelRegistry::Anthropic::DEFAULT_SUMMARIZER ] if resolver.success?
      end

      # Try OpenAI with cheapest model
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

      # Last resort: agent's own provider with cheapest model
      resolver = Providers::Resolver.call(provider_name: @agent.model_provider, agent: @agent)
      if resolver.success?
        cheap =
          case @agent.model_provider
          when "anthropic" then LlmModelRegistry::Anthropic::DEFAULT_SUMMARIZER
          when "openai"    then LlmModelRegistry::OpenAI::DEFAULT_SUMMARIZER
          else @agent.llm_model
          end
        return [ resolver.data[:adapter], cheap ]
      end

      [ nil, nil ]
    end
  end
end
