# frozen_string_literal: true

module Skills
  # Rejects an agent-proposed skill after admin review.
  #
  # Responsibilities:
  #   - Marks the skill with proposal_status "rejected" (remains disabled)
  #   - Resolves the open ApprovalRequest with rejected status
  #   - Broadcasts rejection so the UI updates
  class ProposalRejector
    def self.call(skill:, rejected_by:, notes: nil)
      new(skill:, rejected_by:, notes:).call
    end

    def initialize(skill:, rejected_by:, notes:)
      @skill       = skill
      @rejected_by = rejected_by
      @notes       = notes
    end

    def call
      return ServiceResponse.failure(error: "Skill is not a pending proposal") unless @skill.proposal_status == "pending"

      @skill.update!(
        proposal_status: "rejected",
        proposal_notes: @notes,
        proposal_rejected_at: Time.current,
        proposal_rejected_by: @rejected_by
      )

      resolve_approval_request
      broadcast_rejection

      ServiceResponse.success(data: { skill: @skill })
    rescue StandardError => e
      ServiceResponse.failure(error: "Rejection failed: #{e.message}")
    end

    private

    def resolve_approval_request
      pending_request = ApprovalRequest.pending.find_by(
        action: "create_skill",
        resource: "Skill##{@skill.id}"
      )
      return unless pending_request

      pending_request.update!(
        status: "rejected",
        resolved_at: Time.current,
        resolved_by: @rejected_by.to_s,
        resolution_notes: @notes
      )
    end

    def broadcast_rejection
      ActionCable.server.broadcast(
        "approvals",
        {
          type: "skill_proposal_rejected",
          skill: {
            id: @skill.id,
            name: @skill.name,
            rejected_at: @skill.proposal_rejected_at.iso8601
          }
        }
      )
    end
  end
end
