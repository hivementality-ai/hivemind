# frozen_string_literal: true

module Skills
  # Activates an agent-proposed skill after admin approval.
  #
  # Responsibilities:
  #   - Marks the skill as enabled with proposal_status "approved"
  #   - Assigns the skill to the proposing agent (and optionally the team)
  #   - Resolves any open ApprovalRequest for the skill
  #   - Syncs skill tools for the agent
  class ProposalApprover
    def self.call(skill:, approved_by:, notes: nil)
      new(skill:, approved_by:, notes:).call
    end

    def initialize(skill:, approved_by:, notes:)
      @skill       = skill
      @approved_by = approved_by
      @notes       = notes
    end

    def call
      return ServiceResponse.failure(error: "Skill is not a pending proposal") unless @skill.proposal_status == "pending"

      @skill.update!(
        enabled: true,
        proposal_status: "approved",
        approved_at: Time.current,
        approved_by: @approved_by
      )

      assign_to_agent
      resolve_approval_request
      broadcast_approval

      ServiceResponse.success(data: { skill: @skill })
    rescue StandardError => e
      ServiceResponse.failure(error: "Approval failed: #{e.message}")
    end

    private

    def proposing_agent
      @proposing_agent ||= Agent.find_by(id: @skill.proposed_by_agent_id || @skill.metadata&.dig("created_by_agent_id"))
    end

    def assign_to_agent
      return unless proposing_agent

      AgentSkill.find_or_create_by!(agent: proposing_agent, skill: @skill)

      if @skill.metadata&.dig("share_with_team") && proposing_agent.team
        proposing_agent.team.agents.where.not(id: proposing_agent.id).find_each do |teammate|
          AgentSkill.find_or_create_by!(agent: teammate, skill: @skill)
        end
      end

      Agents::SyncSkillTools.call(agent: proposing_agent)
    end

    def resolve_approval_request
      pending_request = ApprovalRequest.pending.find_by(
        action: "create_skill",
        resource: "Skill##{@skill.id}"
      )
      return unless pending_request

      pending_request.update!(
        status: "approved",
        resolved_at: Time.current,
        resolved_by: @approved_by.to_s,
        resolution_notes: @notes
      )
    end

    def broadcast_approval
      ActionCable.server.broadcast(
        "approvals",
        {
          type: "skill_proposal_approved",
          skill: {
            id: @skill.id,
            name: @skill.name,
            approved_at: @skill.approved_at.iso8601
          }
        }
      )
    end
  end
end
