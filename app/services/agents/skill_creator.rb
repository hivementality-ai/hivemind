# frozen_string_literal: true

module Agents
  class SkillCreator
    def self.call(agent:, name:, summary:, content:, category: nil, share_with_team: false)
      new(agent:, name:, summary:, content:, category:, share_with_team:).call
    end

    def initialize(agent:, name:, summary:, content:, category:, share_with_team:)
      @agent = agent
      @name = name
      @summary = summary
      @content = content
      @category = category
      @share_with_team = share_with_team
    end

    def call
      return ServiceResponse.failure(error: "Name is required") if @name.blank?
      return ServiceResponse.failure(error: "Content is required") if @content.blank?
      return ServiceResponse.failure(error: "Summary is required") if @summary.blank?
      return ServiceResponse.failure(error: "Skill '#{@name}' already exists") if Skill.exists?(name: @name)

      scan_result = SkillSecurityScanner.call(content: @content, name: @name, source: "agent")
      return ServiceResponse.failure(error: "Skill blocked: #{scan_result.data[:blocklist_reasons]}") if scan_result.success? && scan_result.data[:blocked]

      skill = Skill.create!(
        name: @name,
        summary: @summary,
        description: "Created by agent: #{@agent.name}",
        content: @content,
        category: resolve_category,
        builtin: false,
        enabled: false,
        source: "agent",
        security_scan_result: scan_result.success? ? scan_result.data : {},
        metadata: {
          created_by_agent_id: @agent.id,
          created_by_agent_name: @agent.name,
          share_with_team: @share_with_team,
          created_at: Time.current.iso8601
        }
      )

      if scan_result.success? && scan_result.data[:status] == "clean"
        approve_skill(skill)
        ServiceResponse.success(data: {
          output: "Skill '#{@name}' created and auto-approved (security scan clean). It's now active.",
          skill_id: skill.id,
          status: "active"
        })
      else
        create_approval_request(skill, scan_result)
        ServiceResponse.success(data: {
          output: "Skill '#{@name}' created and queued for review. An admin will review it before activation.",
          skill_id: skill.id,
          status: "pending_review"
        })
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Skill creation failed: #{e.message}")
    end

    private

    def resolve_category
      return @category if @category.present? && Skill::CATEGORIES.include?(@category)

      "utilities"
    end

    def approve_skill(skill)
      skill.update!(enabled: true, approved_at: Time.current)
      AgentSkill.find_or_create_by!(agent: @agent, skill: skill)

      if @share_with_team && @agent.team
        @agent.team.agents.where.not(id: @agent.id).find_each do |teammate|
          AgentSkill.find_or_create_by!(agent: teammate, skill: skill)
        end
      end

      Agents::SyncSkillTools.call(agent: @agent)
    end

    def create_approval_request(skill, scan_result)
      Approvals::Request.call(
        agent: @agent,
        action: "create_skill",
        resource: "Skill##{skill.id}",
        params: {
          skill_id: skill.id,
          skill_name: skill.name,
          security_status: scan_result.success? ? scan_result.data[:status] : "scan_failed",
          share_with_team: @share_with_team
        }
      )
    end
  end
end
