# frozen_string_literal: true

module Memory
  class ContextBuilder
    MAX_MEMORY_TOKENS = 2000
    AVG_CHARS_PER_TOKEN = 4 # rough estimate
    MAX_CHARS = MAX_MEMORY_TOKENS * AVG_CHARS_PER_TOKEN

    def self.call(agent:, query:)
      new(agent:, query:).call
    end

    def initialize(agent:, query:)
      @agent = agent
      @query = query
      @budget_remaining = MAX_CHARS
    end

    # Returns a structured string to inject into the system prompt,
    # plus the raw memory entries used (for logging/debugging)
    def call
      sections = []
      all_entries = []

      # Priority 1: User preferences (always included — they shape every response)
      prefs = preference_memories
      if prefs.any?
        section, used = format_section("User Preferences", prefs)
        sections << section
        all_entries.concat(used)
      end

      # Priority 2: Semantic matches (most relevant to current query)
      relevant = relevant_memories
      if relevant.any?
        section, used = format_section("Relevant Context", relevant)
        sections << section
        all_entries.concat(used)
      end

      # Priority 3: Recent episodic summaries (what happened recently)
      recent = recent_episodic
      if recent.any?
        section, used = format_section("Recent History", recent)
        sections << section
        all_entries.concat(used)
      end

      # Touch all retrieved memories
      all_entries.each(&:touch_accessed!)

      context_text = if sections.any?
                       header = "## Your Memories\nUse these naturally in conversation. Don't mention that you're recalling memories.\n\n"
                       header + sections.join("\n\n")
      end

      { context: context_text, entries: all_entries }
    rescue StandardError => e
      Rails.logger.warn("[Memory::ContextBuilder] Failed: #{e.message}")
      { context: nil, entries: [] }
    end

    private

    # All preferences for this agent (they're always relevant)
    def preference_memories
      MemoryEntry.where(agent: @agent)
                 .preferences
                 .by_importance
                 .limit(15)
                 .to_a
    end

    # Semantic search for memories relevant to the current query
    def relevant_memories
      embedding = Memory::Embedding.generate(@query)
      return [] unless embedding

      # Use relevance search (similarity + recency weighted)
      results = MemoryEntry.relevance_search(
        embedding: embedding,
        agent: @agent,
        limit: 10
      )

      # Exclude preferences (already included) and low-importance episodic noise
      results.reject { |e| e.memory_type == "preference" }
             .reject { |e| e.memory_type == "episodic" && e.importance < 0.3 }
    rescue StandardError => e
      Rails.logger.warn("[Memory::ContextBuilder] Semantic search failed: #{e.message}")
      # Keyword fallback
      keyword_fallback
    end

    # Recent episodic memories (last few session summaries)
    def recent_episodic
      MemoryEntry.where(agent: @agent)
                 .episodic
                 .where("importance >= ?", 0.4)
                 .order(created_at: :desc)
                 .limit(5)
                 .to_a
    end

    def keyword_fallback
      keywords = @query.downcase.gsub(/[^a-z0-9\s]/, "").split.reject { |w| w.length < 4 }.first(3)
      return [] if keywords.empty?

      conditions = keywords.map { "LOWER(content) LIKE ?" }
      values = keywords.map { |kw| "%#{MemoryEntry.sanitize_sql_like(kw)}%" }

      MemoryEntry.where(agent: @agent)
                 .where.not(memory_type: "preference")
                 .where(conditions.join(" OR "), *values)
                 .order(created_at: :desc)
                 .limit(5)
                 .to_a
    end

    def format_section(title, entries)
      used = []
      lines = []

      entries.each do |entry|
        line = "- #{entry.content.truncate(300)}"
        break if @budget_remaining - line.length < 0

        lines << line
        used << entry
        @budget_remaining -= line.length
      end

      return [ nil, [] ] if lines.empty?

      [ "### #{title}\n#{lines.join("\n")}", used ]
    end
  end
end
