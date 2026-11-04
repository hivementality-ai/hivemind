# frozen_string_literal: true

module Approvals
  # Runs a connector write once its approval is granted, with the arguments stored
  # on the request, and records the outcome in the audit log.
  class RunConnectorCall
    MAX_LOGGED_OUTPUT = 2000

    # @param approval [ApprovalRequest] an approved "connector_call" request
    # @return [ServiceResponse] the result of Connectors::Executor
    def self.call(approval:)
      new(approval:).call
    end

    def initialize(approval:)
      @approval = approval
    end

    def call
      result = run
      record(result)
      result
    end

    private

    def run
      connector = Connector.find_by(id: params["connector_id"])
      return ServiceResponse.failure(error: "Connector not found") unless connector

      Connectors::Executor.call(
        connector: connector, operation: params["operation"], params: params["arguments"], agent: @approval.agent
      )
    end

    def params
      @approval.params || {}
    end

    def record(result)
      AuditLog.create(
        actor_type: "Agent",
        actor_id: @approval.agent_id,
        action: "connector_call_executed",
        resource: "ApprovalRequest##{@approval.id}",
        metadata: {
          connector_id: params["connector_id"],
          operation: params["operation"],
          success: result.success?,
          output: (result.success? ? result.data[:output] : result.error).to_s.truncate(MAX_LOGGED_OUTPUT)
        }
      )
    end
  end
end
