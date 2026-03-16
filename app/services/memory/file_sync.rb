# frozen_string_literal: true

module Memory
  class FileSync
    MEMORY_BASE = "/workspace/.hivemind/agents"
    MAX_LINES = 150 # Stay under SDK's 200-line MEMORY.md limit
    STALE_AFTER = 5.minutes

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
        return
      end

      FileUtils.mkdir_p(dir)
      write_memory_index(dir)
      write_recent_context(dir) if @query.present?
    rescue StandardError => e
      Rails.logger.warn("[Memory::FileSync] Failed for agent #{@agent.id}: #{e.message}")
    end

    private

    def write_memory_index(dir)
      lines = []
      lines << "# #{@agent.name} — Memory Index"
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

      # Enforce line budget
      content = lines.first(MAX_LINES).join("\n")
      File.write(File.join(dir, "MEMORY.md"), content)
    end

    def write_recent_context(dir)
      recent = MemoryEntry.where(agent: @agent, memory_type: %w[semantic procedural])
                          .where("importance >= ?", 0.5)
                          .order(created_at: :desc)
                          .limit(5)

      lines = [ "# Recent Context", "" ]
      recent.each { |r| lines << "- #{r.content}" }

      File.write(File.join(dir, "recent_context.md"), lines.join("\n"))
    end
  end
end
