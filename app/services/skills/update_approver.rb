# frozen_string_literal: true

module Skills
  # Applies an approved skill update proposal to the skill's content.
  #
  # On approval:
  #   1. Applies proposed_content to the skill
  #   2. Creates a SkillVersion snapshot (with proposal linkage and agent attribution)
  #   3. Marks the proposal as approved
  #   4. Resolves the open ApprovalRequest
  #   5. Broadcasts an ActionCable event so the admin UI updates
  class UpdateApprover
    def self.call(proposal:, approved_by:, notes: nil)
      new(proposal:, approved_by:, notes:).call
    end

    def initialize(proposal:, approved_by:, notes:)
      @proposal    = proposal
      @approved_by = approved_by
      @notes       = notes
    end

    def call
      return ServiceResponse.failure(error: "Proposal is not pending") unless @proposal.pending?

      skill = @proposal.skill

      ActiveRecord::Base.transaction do
        # Suppress the auto-snapshot callback so we can create a richer one
        skill.skip_auto_snapshot!
        skill.update!(content: @proposal.proposed_content)

        SkillVersion.snapshot!(
          skill: skill,
          change_source: "agent_update",
          changed_by_user_id: @approved_by,
          changed_by_agent_id: @proposal.proposed_by_agent_id,
          change_summary: "Agent update approved: #{@proposal.rationale.truncate(120)}",
          update_proposal_id: @proposal.id
        )

        @proposal.update!(
          status: "approved",
          reviewed_by_user_id: @approved_by,
          review_notes: @notes,
          reviewed_at: Time.current
        )
      end

      resolve_approval_request
      broadcast_approval

      ServiceResponse.success(data: { skill: skill, proposal: @proposal })
    rescue StandardError => e
      Rails.logger.error("[Skills::UpdateApprover] Failed for proposal ##{@proposal.id}: #{e.full_message}")
      ServiceResponse.failure(error: "Approval failed: #{e.message}")
    end

    private

    def resolve_approval_request
      pending = ApprovalRequest.pending.find_by(
        action: "update_skill",
        resource: "SkillUpdateProposal##{@proposal.id}"
      )
      return unless pending

      pending.update!(
        status: "approved",
        resolved_at: Time.current,
        resolved_by: @approved_by.to_s,
        resolution_notes: @notes
      )
    rescue StandardError => e
      Rails.logger.warn("[Skills::UpdateApprover] Failed to resolve approval request: #{e.message}")
    end

    def broadcast_approval
      ActionCable.server.broadcast(
        "approvals",
        {
          type: "skill_update_approved",
          proposal: {
            id: @proposal.id,
            skill_id: @proposal.skill_id,
            skill_name: @proposal.skill.name,
            approved_at: Time.current.iso8601
          }
        }
      )
    rescue StandardError => e
      Rails.logger.warn("[Skills::UpdateApprover] Broadcast failed: #{e.message}")
    end
  end
end
