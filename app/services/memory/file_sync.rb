# frozen_string_literal: true

module Memory
  class FileSync
    MEMORY_BASE = "/app/agents-shared/.hivemind/agents"
    STALE_AFTER = 30.minutes

    def self.call(agent:, query: nil, force: false)
      new(agent: agent, query: query, force: force).call
    end

    def initialize(agent:, query: nil, force: false)
      @agent = agent
      @query = query
      @force = force
    end

    def call
      dir = File.join(MEMORY_BASE, @agent.id.to_s, "memory")
      memory_file = File.join(dir, "MEMORY.md")

      # Skip if file exists and is fresh (written within STALE_AFTER)
      if !@force && File.exist?(memory_file) && File.mtime(memory_file) > STALE_AFTER.ago
        Rails.logger.debug("[Memory::FileSync] Skipping agent #{@agent.slug} — MEMORY.md is fresh (#{((Time.current - File.mtime(memory_file)) / 60).round}min old)")
        return
      end

      FileUtils.mkdir_p(dir)

      # Use LLM summarizer to produce a clean, deduplicated, prioritized MEMORY.md
      summarized = Memory::Summarizer.call(agent: @agent)

      if summarized.present?
        File.open(memory_file, "w+") { |f| f.write(summarized) }
        Rails.logger.info("[Memory::FileSync] Wrote summarized MEMORY.md for agent #{@agent.slug} (#{summarized.lines.count} lines)")
      else
        # Fallback to raw dump if summarizer fails (no provider, etc.)
        write_raw_memory(memory_file)
        Rails.logger.info("[Memory::FileSync] Wrote raw MEMORY.md for agent #{@agent.slug} (summarizer unavailable)")
      end

      if @query.present?
        write_recent_context(dir)
        Rails.logger.info("[Memory::FileSync] Wrote recent_context.md for agent #{@agent.slug}")
      end
    rescue StandardError => e
      Rails.logger.warn("[Memory::FileSync] Failed for agent #{@agent.id}: #{e.message}")
    end

    private

    def write_raw_memory(memory_file)
      lines = []
      lines << "# #{@agent.name} — Memory"
      lines << ""

      prefs = MemoryEntry.where(agent: @agent).preferences.by_importance.limit(15)
      if prefs.any?
        lines << "## Preferences"
        prefs.each { |p| lines << "- #{p.content}" }
        lines << ""
      end

      facts = MemoryEntry.where(agent: @agent, memory_type: "semantic")
                         .where("importance >= ?", 0.7)
                         .order(importance: :desc)
                         .limit(10)
      if facts.any?
        lines << "## Key Knowledge"
        facts.each { |f| lines << "- #{f.content}" }
        lines << ""
      end

      procedures = MemoryEntry.where(agent: @agent, memory_type: "procedural")
                              .where("importance >= ?", 0.6)
                              .order(importance: :desc)
                              .limit(5)
      if procedures.any?
        lines << "## Procedures"
        procedures.each { |p| lines << "- #{p.content}" }
      end

      File.open(memory_file, "w+") { |f| f.write(lines.join("\n")) }
    end

    def write_recent_context(dir)
      recent = MemoryEntry.where(agent: @agent, memory_type: %w[semantic procedural])
                          .where("importance >= ?", 0.5)
                          .order(created_at: :desc)
                          .limit(5)

      lines = [ "# Recent Context", "" ]
      recent.each { |r| lines << "- #{r.content}" }

      File.open(File.join(dir, "recent_context.md"), "w+") { |f| f.write(lines.join("\n")) }
    end
  end
end
