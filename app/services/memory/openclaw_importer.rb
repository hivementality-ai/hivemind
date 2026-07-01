# frozen_string_literal: true

module Memory
  class OpenclawImporter
    WORKSPACE_FILES = %w[SOUL.md MEMORY.md USER.md TOOLS.md AGENTS.md IDENTITY.md HEARTBEAT.md].freeze

    def self.call(workspace_path:, agent_slug: nil)
      new(workspace_path:, agent_slug:).call
    end

    def initialize(workspace_path:, agent_slug: nil)
      @workspace_path = workspace_path
      @agent_slug = agent_slug
    end

    def call
      # 1. Parse agent identity
      identity = parse_identity
      agent_name = identity[:name] || "Imported Agent"

      # 2. Find or create agent
      agent = find_or_create_agent(name: agent_name, slug: @agent_slug)

      # 3. Apply SOUL.md as system prompt
      apply_soul(agent)

      # 4. Copy workspace files to shared workspace
      files_copied = copy_workspace_files

      # 5. Import memories from MEMORY.md
      memory_count = import_memory_file(agent, "MEMORY.md")

      # 6. Import memories from memory/*.md daily files
      memory_count += import_daily_memories(agent)

      {
        success: true,
        agent_name: agent.name,
        agent_slug: agent.slug,
        memories_created: memory_count,
        files_copied: files_copied
      }
    rescue StandardError => e
      Rails.logger.error("[OpenclawImporter] Failed: #{e.message}")
      { success: false, error: e.message }
    end

    private

    def parse_identity
      identity_path = File.join(@workspace_path, "IDENTITY.md")
      return {} unless File.exist?(identity_path)

      content = File.read(identity_path)
      name = content.match(/\*\*Name:\*\*\s*(.+)/)&.captures&.first&.strip
      emoji = content.match(/\*\*Emoji:\*\*\s*(.+)/)&.captures&.first&.strip
      vibe = content.match(/\*\*Vibe:\*\*\s*(.+)/)&.captures&.first&.strip

      { name: name, emoji: emoji, vibe: vibe }
    end

    def find_or_create_agent(name:, slug: nil)
      slug ||= name.parameterize

      agent = Agent.find_by(slug: slug)
      if agent
        Rails.logger.info("[OpenclawImporter] Found existing agent: #{agent.name} (#{agent.slug})")
        return agent
      end

      # Create new agent
      agent = Agent.create!(
        name: name,
        slug: slug,
        llm_model: LlmModelRegistry::Anthropic::DEFAULT_MID,
        model_provider: "anthropic",
        enabled: true,
        role: "General Assistant",
        team_id: Team.first&.id || Team.create!(name: "Default").id
      )

      Rails.logger.info("[OpenclawImporter] Created agent: #{agent.name} (#{agent.slug})")
      agent
    end

    def apply_soul(agent)
      soul_path = File.join(@workspace_path, "SOUL.md")
      return unless File.exist?(soul_path)

      soul_content = File.read(soul_path).strip
      return if soul_content.blank?

      # SOUL.md goes into custom_instructions — the user-facing context field
      if agent.custom_instructions.blank?
        agent.update!(custom_instructions: soul_content)
        Rails.logger.info("[OpenclawImporter] Applied SOUL.md as custom instructions")
      end
    end

    def copy_workspace_files
      dest = File.expand_path("~/hivemind-agents-shared")
      FileUtils.mkdir_p(dest)
      count = 0

      # Copy files
      WORKSPACE_FILES.each do |filename|
        src = File.join(@workspace_path, filename)
        next unless File.exist?(src)

        FileUtils.cp(src, File.join(dest, filename))
        count += 1
      end

      # Copy directories
      %w[skills memory].each do |dir|
        src = File.join(@workspace_path, dir)
        next unless File.directory?(src)

        FileUtils.cp_r(src, File.join(dest, dir))
        count += 1
      end

      count
    end

    def import_memory_file(agent, filename)
      filepath = File.join(@workspace_path, filename)
      return 0 unless File.exist?(filepath)

      content = File.read(filepath).strip
      return 0 if content.blank?

      chunks = chunk_markdown(content)
      count = 0

      chunks.each do |chunk|
        next if chunk[:content].strip.length < 20 # Skip tiny fragments

        entry = MemoryEntry.create!(
          agent: agent,
          content: chunk[:content],
          memory_type: guess_memory_type(chunk[:content]),
          importance: guess_importance(chunk[:content]),
          metadata: {
            source_file: filename,
            section: chunk[:heading],
            imported_from: "openclaw",
            imported_at: Time.current.iso8601
          }
        )

        MemoryEmbeddingJob.perform_later(entry.id)
        count += 1
      end

      Rails.logger.info("[OpenclawImporter] Imported #{count} memories from #{filename}")
      count
    end

    def import_daily_memories(agent)
      memory_dir = File.join(@workspace_path, "memory")
      return 0 unless File.directory?(memory_dir)

      count = 0

      Dir.glob(File.join(memory_dir, "*.md")).sort.each do |filepath|
        filename = File.basename(filepath)
        count += import_memory_file(agent, File.join("memory", filename))
      end

      count
    end

    # Split markdown by ## headers into discrete chunks
    def chunk_markdown(content)
      chunks = []
      current_heading = nil
      current_lines = []

      content.lines.each do |line|
        if line.match?(/\A##\s/)
          # Save previous chunk
          if current_lines.any?
            chunks << { heading: current_heading, content: current_lines.join.strip }
          end
          current_heading = line.strip.gsub(/\A#+\s*/, "")
          current_lines = []
        else
          current_lines << line
        end
      end

      # Save last chunk
      if current_lines.any?
        chunks << { heading: current_heading, content: current_lines.join.strip }
      end

      # If no headers found, treat the whole file as one chunk
      if chunks.empty? && content.strip.present?
        chunks << { heading: nil, content: content.strip }
      end

      chunks
    end

    # Simple heuristic to guess memory type from content
    def guess_memory_type(content)
      lowered = content.downcase

      if lowered.match?(/prefer|like|dislike|always use|don't like|style|tone|voice/)
        "preference"
      elsif lowered.match?(/run |deploy|install|command|docker|bundle|rake|git |ssh |curl /)
        "procedural"
      elsif lowered.match?(/name is|works at|lives in|born |email|phone|timezone|pronoun/)
        "semantic"
      else
        "episodic"
      end
    end

    # Simple heuristic to guess importance
    def guess_importance(content)
      lowered = content.downcase

      if lowered.match?(/never|always|important|critical|⚠️|🔴|do not|don't ever/)
        0.9
      elsif lowered.match?(/prefer|name is|works at|rule|password|key|token/)
        0.8
      elsif lowered.match?(/deploy|install|setup|config/)
        0.7
      elsif lowered.match?(/decided|built|created|launched|shipped/)
        0.6
      else
        0.5
      end
    end
  end
end
