# frozen_string_literal: true

module ApprovalsHelper
  # Total pending approval count for the nav badge.
  # ponytail: Redis keys scan is O(n); acceptable for low vault-confirmation volume.
  def pending_approvals_count
    ar_count = ApprovalRequest.pending.not_expired.count
    sup_count = SkillUpdateProposal.pending.count
    vault_count = begin
      Redis.current.keys("#{Vault::WriteConfirmation::REDIS_NAMESPACE}:*").size
    rescue StandardError
      0
    end
    ar_count + sup_count + vault_count
  end
end
