# frozen_string_literal: true

module Approvals
  class Request
    def self.call(agent:, action:, resource:, params: {}, expires_in: 24.hours)
      new(agent:, action:, resource:, params:, expires_in:).call
    end

    def initialize(agent:, action:, resource:, params: {}, expires_in: 24.hours)
      @agent = agent
      @action = action
      @resource = resource
      @params = params
      @expires_in = expires_in
    end

    def call
      approval = ApprovalRequest.create(
        agent: @agent,
        action: @action,
        resource: @resource,
        params: @params,
        expires_at: Time.current + @expires_in
      )

      if approval.persisted?
        broadcast_to_ui(approval)
        log_audit(approval)
        ServiceResponse.success(data: { approval: })
      else
        ServiceResponse.failure(error: approval.errors.full_messages)
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Approval request failed: #{e.message}")
    end

    private

    def broadcast_to_ui(approval)
      ActionCable.server.broadcast(
        "approvals",
        {
          type: "approval_requested",
          approval: {
            id: approval.id,
            agent: {
              id: @agent.id,
              name: @agent.name,
              role: @agent.role
            },
            action: @action,
            resource: @resource,
            params: @params,
            requested_at: approval.requested_at.iso8601,
            expires_at: approval.expires_at&.iso8601
          }
        }
      )
    end

    def log_audit(approval)
      AuditLog.create(
        actor_type: "Agent",
        actor_id: @agent.id,
        action: "approval_requested",
        resource_type: "ApprovalRequest",
        resource_id: approval.id,
        metadata: {
          action: @action,
          resource: @resource,
          params: @params
        }
      )
    end
  end
end
