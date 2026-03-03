# frozen_string_literal: true

module OpenClaw
  class SkillParser
    def self.call(workspace_path:, agent:)
      new(workspace_path:, agent:).call
    end

    def initialize(workspace_path:, agent:)
      @workspace_path = workspace_path
      @agent = agent
    end

    def call
      skills_dir = File.join(@workspace_path, "skills")
      return ServiceResponse.success(data: { imported: [], skipped: [], scan_results: [] }) unless File.directory?(skills_dir)

      imported = []
      skipped = []
      scan_results = []

      skill_files = Dir.glob(File.join(skills_dir, "*.SKILL.md")) + Dir.glob(File.join(skills_dir, "*.md"))
      skill_files.uniq.each do |filepath|
        text = File.read(filepath)
        filename = File.basename(filepath)

        skill = Skill.from_skill_md(text)
        next if skill.name.blank?

        # Run security scan
        scan_result = SkillSecurityScanner.call(content: skill.content, name: skill.name, source: "openclaw")
        scan_results << { name: skill.name, file: filename, result: scan_result.data }

        status = scan_result.data[:status] || scan_result.data["status"]

        if %w[blocked flagged].include?(status)
          skipped << { name: skill.name, file: filename, reason: "Security scan: #{status}" }
          next
        end

        # Find or initialize for idempotent re-runs
        existing = Skill.find_by(name: skill.name)
        if existing
          existing.assign_attributes(
            content: skill.content,
            description: skill.description,
            summary: skill.summary,
            category: skill.category,
            source: "openclaw",
            security_scan_result: scan_result.data
          )
          existing.save!
          record = existing
        else
          skill.source = "openclaw"
          skill.security_scan_result = scan_result.data
          skill.save!
          record = skill
        end

        # Create AgentSkill join if not exists
        AgentSkill.find_or_create_by!(agent: @agent, skill: record)
        imported << { name: record.name, file: filename, status: status }
      end

      ServiceResponse.success(data: { imported: imported, skipped: skipped, scan_results: scan_results })
    rescue StandardError => e
      ServiceResponse.failure(error: "Skill import failed: #{e.message}")
    end
  end
end
