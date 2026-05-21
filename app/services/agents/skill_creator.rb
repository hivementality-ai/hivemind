# frozen_string_literal: true

module Agents
  # Creates a new skill proposed by an agent.
  #
  # Phase 4 behaviour: all agent-authored skills require explicit admin approval
  # before activation (proposal_status: "pending"). The admin reviews via the
  # skill proposals UI and approves or rejects. No skill is auto-activated.
  #
  # Pipeline:
  #   1. Quality guardrails (ProposalValidator) — fast structural checks
  #   2. Security scan (SkillSecurityScanner) — content analysis
  #   3. Blocked skills are rejected immediately; all others stored as pending
  #   4. ApprovalRequest created → admin notified via ActionCable
  class SkillCreator
    def self.call(agent:, name:, summary:, content:, category: nil, share_with_team: false)
      new(agent:, name:, summary:, content:, category:, share_with_team:).call
    end

    def initialize(agent:, name:, summary:, content:, category:, share_with_team:)
      @agent         = agent
      @name          = name.to_s.strip
      @summary       = summary.to_s.strip
      @content       = content.to_s.strip
      @category      = category
      @share_with_team = share_with_team
    end

    def call
      return ServiceResponse.failure(error: "Skill '#{@name}' already exists") if Skill.exists?(name: @name)

      quality_result = Skills::ProposalValidator.call(
        name: @name, summary: @summary, content: @content, category: @category.to_s
      )
      return ServiceResponse.failure(error: "Skill proposal rejected: #{quality_result.error}") unless quality_result.success?

      scan_result = SkillSecurityScanner.call(content: @content, name: @name, source: "agent")

      if scan_result.success? && scan_result.data[:blocked]
        return ServiceResponse.failure(
          error: "Skill blocked by security scan: #{scan_result.data[:blocklist_reasons]&.join(', ')}"
        )
      end

      skill = Skill.create!(
        name: @name,
        summary: @summary,
        description: "Proposed by agent: #{@agent.name}",
        content: @content,
        category: resolve_category,
        builtin: false,
        enabled: false,
        source: "agent",
        proposal_status: "pending",
        proposed_by_agent_id: @agent.id,
        proposed_at: Time.current,
        security_scan_result: scan_result.success? ? scan_result.data : {},
        metadata: {
          created_by_agent_id: @agent.id,
          created_by_agent_name: @agent.name,
          share_with_team: @share_with_team,
          created_at: Time.current.iso8601
        }
      )

      create_approval_request(skill, scan_result)

      ServiceResponse.success(data: {
        output: "Skill '#{@name}' submitted for admin review. It will be available once approved.",
        skill_id: skill.id,
        status: "pending_review"
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Skill creation failed: #{e.message}")
    end

    private

    def resolve_category
      return @category if @category.present? && Skill::CATEGORIES.include?(@category)

      "utilities"
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
