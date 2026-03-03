# frozen_string_literal: true

module OpenClaw
  class MigrationReport
    attr_accessor :workspace_path, :agent, :identity_imported,
                  :memories_created, :memory_files_processed,
                  :skills_imported, :skills_skipped, :skill_scan_results,
                  :channels_created, :channels_skipped,
                  :sessions_created, :tools_created, :tools_skipped,
                  :markers_found, :warnings

    def initialize(workspace_path:)
      @workspace_path = workspace_path
      @agent = nil
      @identity_imported = false
      @memories_created = 0
      @memory_files_processed = 0
      @skills_imported = []
      @skills_skipped = []
      @skill_scan_results = []
      @channels_created = []
      @channels_skipped = []
      @sessions_created = 0
      @tools_created = []
      @tools_skipped = []
      @markers_found = []
      @warnings = []
    end

    def add_warning(msg)
      @warnings << msg
    end

    def success?
      identity_imported && warnings.none? { |w| w.start_with?("FATAL:") }
    end

    def to_console
      lines = []
      lines << "OpenClaw Migration Report"
      lines << "=" * 40
      lines << "Workspace: #{workspace_path}"
      lines << "Agent: #{agent&.name || 'N/A'} (#{agent&.slug || 'N/A'})"
      lines << "Identity imported: #{identity_imported}"
      lines << ""
      lines << "Memories: #{memories_created} created (#{memory_files_processed} files processed)"
      lines << "Skills: #{skills_imported.size} imported, #{skills_skipped.size} skipped"
      lines << "Channels: #{channels_created.size} created (disabled), #{channels_skipped.size} skipped"
      lines << "Sessions: #{sessions_created} archived"
      lines << "Tools: #{tools_created.size} created, #{tools_skipped.size} skipped"
      lines << ""

      if skills_skipped.any?
        lines << "Skipped skills:"
        skills_skipped.each { |s| lines << "  - #{s[:name]}: #{s[:reason]}" }
        lines << ""
      end

      if warnings.any?
        lines << "Warnings:"
        warnings.each { |w| lines << "  ! #{w}" }
        lines << ""
      end

      lines << "Markers found: #{markers_found.join(', ')}" if markers_found.any?
      lines << "Result: #{success? ? 'SUCCESS' : 'COMPLETED WITH WARNINGS'}"
      lines.join("\n")
    end

    def to_markdown
      lines = []
      lines << "# OpenClaw Migration Report"
      lines << ""
      lines << "- **Workspace:** `#{workspace_path}`"
      lines << "- **Agent:** #{agent&.name || 'N/A'} (`#{agent&.slug || 'N/A'}`)"
      lines << "- **Identity imported:** #{identity_imported}"
      lines << ""
      lines << "## Summary"
      lines << ""
      lines << "| Artifact | Imported | Skipped |"
      lines << "|----------|----------|---------|"
      lines << "| Memories | #{memories_created} | - |"
      lines << "| Skills | #{skills_imported.size} | #{skills_skipped.size} |"
      lines << "| Channels | #{channels_created.size} | #{channels_skipped.size} |"
      lines << "| Sessions | #{sessions_created} | - |"
      lines << "| Tools | #{tools_created.size} | #{tools_skipped.size} |"
      lines << ""

      if skills_skipped.any?
        lines << "## Skipped Skills"
        lines << ""
        skills_skipped.each { |s| lines << "- **#{s[:name]}**: #{s[:reason]}" }
        lines << ""
      end

      if warnings.any?
        lines << "## Warnings"
        lines << ""
        warnings.each { |w| lines << "- #{w}" }
        lines << ""
      end

      if markers_found.any?
        lines << "## Markers Found"
        lines << ""
        lines << markers_found.map { |m| "`#{m}`" }.join(", ")
        lines << ""
      end

      lines << "---"
      lines << ""
      lines << "Result: **#{success? ? 'SUCCESS' : 'COMPLETED WITH WARNINGS'}**"
      lines.join("\n")
    end

    def to_h
      {
        workspace_path: workspace_path,
        agent_name: agent&.name,
        agent_slug: agent&.slug,
        identity_imported: identity_imported,
        memories_created: memories_created,
        memory_files_processed: memory_files_processed,
        skills_imported: skills_imported.map { |s| s[:name] },
        skills_skipped: skills_skipped,
        skill_scan_results: skill_scan_results,
        channels_created: channels_created.map { |c| c[:name] },
        channels_skipped: channels_skipped,
        sessions_created: sessions_created,
        tools_created: tools_created.map { |t| t[:name] },
        tools_skipped: tools_skipped,
        markers_found: markers_found,
        warnings: warnings,
        success: success?
      }
    end
  end
end
