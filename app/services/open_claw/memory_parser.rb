# frozen_string_literal: true

module OpenClaw
  class MemoryParser
    def self.call(workspace_path:, agent:, dry_run: false)
      new(workspace_path:, agent:, dry_run:).call
    end

    def initialize(workspace_path:, agent:, dry_run: false)
      @workspace_path = workspace_path
      @agent = agent
      @dry_run = dry_run
    end

    def call
      count = 0
      files_processed = 0

      # Import MEMORY.md
      memory_path = File.join(@workspace_path, "MEMORY.md")
      if File.exist?(memory_path)
        count += import_memory_file("MEMORY.md")
        files_processed += 1
      end

      # Import memory/*.md daily files
      memory_dir = File.join(@workspace_path, "memory")
      if File.directory?(memory_dir)
        Dir.glob(File.join(memory_dir, "*.md")).sort.each do |filepath|
          filename = File.join("memory", File.basename(filepath))
          imported = import_memory_file(filename)
          count += imported
          files_processed += 1 if imported > 0
        end
      end

      ServiceResponse.success(data: { count: count, files_processed: files_processed })
    rescue StandardError => e
      ServiceResponse.failure(error: "Memory import failed: #{e.message}")
    end

    private

    def import_memory_file(filename)
      filepath = File.join(@workspace_path, filename)
      return 0 unless File.exist?(filepath)

      content = File.read(filepath).strip
      return 0 if content.blank?

      chunks = chunk_markdown(content)
      count = 0

      chunks.each do |chunk|
        next if chunk[:content].strip.length < 20

        entry = MemoryEntry.create!(
          agent: @agent,
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

        MemoryEmbeddingJob.perform_later(entry.id) unless @dry_run
        count += 1
      end

      count
    end

    def chunk_markdown(content)
      chunks = []
      current_heading = nil
      current_lines = []

      content.lines.each do |line|
        if line.match?(/\A##\s/)
          if current_lines.any?
            chunks << { heading: current_heading, content: current_lines.join.strip }
          end
          current_heading = line.strip.gsub(/\A#+\s*/, "")
          current_lines = []
        else
          current_lines << line
        end
      end

      if current_lines.any?
        chunks << { heading: current_heading, content: current_lines.join.strip }
      end

      if chunks.empty? && content.strip.present?
        chunks << { heading: nil, content: content.strip }
      end

      chunks
    end

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

    def guess_importance(content)
      lowered = content.downcase

      if lowered.match?(/never|always|important|critical|do not|don't ever/)
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
