# frozen_string_literal: true

module Skills
  # Submits an agent-proposed update to an existing skill's content.
  #
  # The agent provides updated content and a rationale explaining the improvement.
  # The current skill content is snapshotted as `original_content` for diff rendering.
  # A SkillUpdateProposal record is created in "pending" status, and an ApprovalRequest
  # is raised so an admin can review, approve, or reject via the UI.
  #
  # No skill content is changed until an admin approves the proposal.
  class UpdateProposer
    MAX_CONTENT_LENGTH = 50_000

    def self.call(agent:, skill_name:, proposed_content:, rationale:)
      new(agent:, skill_name:, proposed_content:, rationale:).call
    end

    def initialize(agent:, skill_name:, proposed_content:, rationale:)
      @agent            = agent
      @skill_name       = skill_name.to_s.strip
      @proposed_content = proposed_content.to_s.strip
      @rationale        = rationale.to_s.strip
    end

    def call
      skill = Skill.find_by(name: @skill_name)
      return ServiceResponse.failure(error: "Skill '#{@skill_name}' not found") unless skill

      return ServiceResponse.failure(error: "Proposed content is blank") if @proposed_content.blank?
      return ServiceResponse.failure(error: "Rationale is required") if @rationale.blank?
      return ServiceResponse.failure(error: "Proposed content exceeds maximum length") if @proposed_content.length > MAX_CONTENT_LENGTH
      return ServiceResponse.failure(error: "Proposed content is identical to current content") if @proposed_content == skill.content

      if skill.skill_update_proposals.pending.exists?
        return ServiceResponse.failure(
          error: "Skill '#{@skill_name}' already has a pending update proposal. Wait for it to be reviewed."
        )
      end

      proposal = SkillUpdateProposal.create!(
        skill: skill,
        proposed_by_agent: @agent,
        proposed_content: @proposed_content,
        original_content: skill.content,
        rationale: @rationale,
        status: "pending"
      )

      create_approval_request(skill, proposal)

      ServiceResponse.success(data: {
        output: "Update proposal for skill '#{@skill_name}' submitted for admin review (proposal ##{proposal.id}).",
        proposal_id: proposal.id,
        skill_name: @skill_name,
        status: "pending_review"
      })
    rescue StandardError => e
      Rails.logger.error("[Skills::UpdateProposer] Failed for '#{@skill_name}': #{e.full_message}")
      ServiceResponse.failure(error: "Failed to submit update proposal: #{e.message}")
    end

    private

    def create_approval_request(skill, proposal)
      Approvals::Request.call(
        agent: @agent,
        action: "update_skill",
        resource: "SkillUpdateProposal##{proposal.id}",
        params: {
          skill_id: skill.id,
          skill_name: skill.name,
          proposal_id: proposal.id,
          rationale: @rationale.truncate(200)
        }
      )
    rescue StandardError => e
      Rails.logger.warn("[Skills::UpdateProposer] Failed to create approval request: #{e.message}")
    end
  end
end
