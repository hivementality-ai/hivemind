# frozen_string_literal: true

module ClawHub
  class SkillInstaller
    def self.call(slug:, version: nil, user:)
      new(slug, version, user).call
    end

    def initialize(slug, version, user)
      @slug = slug
      @version = version
      @user = user
      @client = Client.new
    end

    def call
      skill_data = @client.get_skill(slug: @slug)
      skill_md_path = find_skill_md_path(skill_data)
      content = @client.get_skill_file(slug: @slug, path: skill_md_path, version: @version)

      skill = Skill.from_skill_md(content)
      skill.name = skill_data.dig("skill", "displayName") || skill_data.dig("skill", "slug") if skill.name.blank?
      skill.source = "clawhub"
      skill.source_url = "#{Client::BASE_URL}/skills/#{@slug}"

      scan_result = SkillSecurityScanner.call(content: skill.content, name: skill.name, source: "clawhub")

      unless scan_result.success?
        return ServiceResponse.failure(error: "Security scan failed: #{scan_result.error}")
      end

      status = scan_result.data[:status]

      if status == "blocked"
        return ServiceResponse.success(data: { skill: nil, scan_result: scan_result.data, status: "blocked" })
      end

      if status == "clean"
        save_skill(skill, scan_result.data)
      else
        ServiceResponse.success(data: {
          skill: nil,
          scan_result: scan_result.data,
          status: "pending_review",
          pending_attributes: {
            name: skill.name,
            description: skill.description,
            summary: skill.summary,
            content: skill.content,
            category: skill.category,
            source: "clawhub",
            source_url: skill.source_url
          }
        })
      end
    rescue ClawHub::ApiError => e
      ServiceResponse.failure(error: "ClawHub API error: #{e.message}")
    rescue StandardError => e
      ServiceResponse.failure(error: "Installation failed: #{e.message}")
    end

    private

    def find_skill_md_path(skill_data)
      files = skill_data.dig("latestVersion", "files") || skill_data.dig("version", "files")
      if files.is_a?(Array)
        skill_file = files.find { |f| f.to_s.end_with?(".SKILL.md") }
        return skill_file if skill_file
      end
      "#{@slug}.SKILL.md"
    end

    def save_skill(skill, scan_data)
      existing = Skill.find_clawhub(source_url: skill.source_url, name: skill.name)

      attrs = {
        description: skill.description,
        summary: skill.summary,
        content: skill.content,
        category: skill.category,
        source: "clawhub",
        source_url: skill.source_url,
        security_scan_result: scan_data
      }

      if existing
        existing.update!(attrs)
        ServiceResponse.success(data: { skill: existing, scan_result: scan_data, status: "installed" })
      else
        skill.assign_attributes(attrs)
        skill.save!
        ServiceResponse.success(data: { skill: skill, scan_result: scan_data, status: "installed" })
      end
    end
  end
end
