# frozen_string_literal: true

module Approvals
  class Resolve
    def self.call(approval_id:, decision:, resolved_by:, notes: nil)
      new(approval_id:, decision:, resolved_by:, notes:).call
    end

    def initialize(approval_id:, decision:, resolved_by:, notes: nil)
      @approval_id = approval_id
      @decision = decision
      @resolved_by = resolved_by
      @notes = notes
    end

    def call
      approval = ApprovalRequest.find_by(id: @approval_id)
      return ServiceResponse.failure(error: "Approval request not found") unless approval
      return ServiceResponse.failure(error: "Approval request already resolved") unless approval.pending?
      return ServiceResponse.failure(error: "Approval request expired") if approval.expired?
      return ServiceResponse.failure(error: "Invalid decision") unless %w[approved rejected].include?(@decision)

      approval.update!(
        status: @decision,
        resolved_at: Time.current,
        resolved_by: @resolved_by,
        resolution_notes: @notes
      )

      broadcast_resolution(approval)
      log_audit(approval)
      execute_pending_action(approval) if @decision == "approved"

      ServiceResponse.success(data: { approval: })
    rescue StandardError => e
      ServiceResponse.failure(error: "Resolution failed: #{e.message}")
    end

    private

    def broadcast_resolution(approval)
      ActionCable.server.broadcast(
        "approvals",
        {
          type: "approval_resolved",
          approval: {
            id: approval.id,
            status: approval.status,
            resolved_at: approval.resolved_at.iso8601,
            resolved_by: @resolved_by,
            notes: @notes
          }
        }
      )
    end

    def log_audit(approval)
      AuditLog.create(
        actor_type: "User",
        actor_id: @resolved_by,
        action: "approval_#{@decision}",
        resource_type: "ApprovalRequest",
        resource_id: approval.id,
        metadata: {
          original_action: approval.action,
          resource: approval.resource,
          params: approval.params,
          notes: @notes
        }
      )
    end

    def execute_pending_action(approval)
      # This is where the approved action would be executed
      # The implementation depends on the action type
      Rails.logger.info("Executing approved action: #{approval.action} on #{approval.resource}")

      # Future: dispatch to appropriate service based on approval.action
      # Example:
      # case approval.action
      # when "delete_file"
      #   Files::Delete.call(**approval.params.symbolize_keys)
      # when "send_message"
      #   Messages::Send.call(**approval.params.symbolize_keys)
      # end
    end
  end
end
