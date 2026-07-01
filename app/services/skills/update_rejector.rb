# frozen_string_literal: true

module Skills
  # Rejects a pending skill update proposal without modifying the skill.
  class UpdateRejector
    def self.call(proposal:, rejected_by:, notes: nil)
      new(proposal:, rejected_by:, notes:).call
    end

    def initialize(proposal:, rejected_by:, notes:)
      @proposal    = proposal
      @rejected_by = rejected_by
      @notes       = notes
    end

    def call
      return ServiceResponse.failure(error: "Proposal is not pending") unless @proposal.pending?

      @proposal.update!(
        status: "rejected",
        reviewed_by_user_id: @rejected_by,
        review_notes: @notes,
        reviewed_at: Time.current
      )

      resolve_approval_request
      broadcast_rejection

      ServiceResponse.success(data: { proposal: @proposal })
    rescue StandardError => e
      Rails.logger.error("[Skills::UpdateRejector] Failed for proposal ##{@proposal.id}: #{e.full_message}")
      ServiceResponse.failure(error: "Rejection failed: #{e.message}")
    end

    private

    def resolve_approval_request
      pending = ApprovalRequest.pending.find_by(
        action: "update_skill",
        resource: "SkillUpdateProposal##{@proposal.id}"
      )
      return unless pending

      pending.update!(
        status: "rejected",
        resolved_at: Time.current,
        resolved_by: @rejected_by.to_s,
        resolution_notes: @notes
      )
    rescue StandardError => e
      Rails.logger.warn("[Skills::UpdateRejector] Failed to resolve approval request: #{e.message}")
    end

    def broadcast_rejection
      ActionCable.server.broadcast(
        "approvals",
        {
          type: "skill_update_rejected",
          proposal: {
            id: @proposal.id,
            skill_id: @proposal.skill_id,
            skill_name: @proposal.skill.name,
            rejected_at: Time.current.iso8601
          }
        }
      )
    rescue StandardError => e
      Rails.logger.warn("[Skills::UpdateRejector] Broadcast failed: #{e.message}")
    end
  end
end
