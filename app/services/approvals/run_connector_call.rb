# frozen_string_literal: true

module Approvals
  # Runs a connector write once its approval is granted, with the arguments stored
  # on the request. The outcome goes to the audit log, back to the approver, and
  # into the chat session that asked for the call.
  class RunConnectorCall
    MAX_OUTCOME_CHARS = 300
    MAX_LOGGED_OUTPUT = 2000

    # @param approval [ApprovalRequest] an approved "connector_call" request
    # @return [ServiceResponse] success carrying +data[:outcome]+, one line telling the approver
    #   whether the call ran and how it went, and +data[:succeeded]+
    def self.call(approval:)
      new(approval:).call
    end

    def initialize(approval:)
      @approval = approval
    end

    def call
      result = run
      outcome = outcome_line(result)
      record(result)
      notify_session(outcome)
      ServiceResponse.success(data: { outcome: outcome, succeeded: result.success? })
    end

    private

    def run
      connector = Connector.find_by(id: params["connector_id"])
      return ServiceResponse.failure(error: "Connector not found") unless connector
      return ServiceResponse.failure(error: "Connector #{connector.slug} is disabled") unless connector.enabled?
      @ran = true
      Connectors::Executor.call(
        connector: connector, operation: params["operation"], params: params["arguments"], agent: @approval.agent
      )
    end

    def params
      @approval.params || {}
    end

    def request_label
      "#{params['method']} #{params['path']} on #{params['connector_name']}"
    end

    def outcome_line(result)
      return "Did not run #{request_label}: #{result.error}" unless @ran
      return "Ran #{request_label}: succeeded#{detail(result.data[:output])}" if result.success?

      "Ran #{request_label}: failed: #{result.error.to_s.truncate(MAX_OUTCOME_CHARS)}"
    end

    def detail(output)
      text = output.to_s.strip
      text.empty? ? "" : " (#{text.truncate(MAX_OUTCOME_CHARS)})"
    end

    def notify_session(outcome)
      session = Session.find_by(id: params["session_id"])
      return unless session

      message = "Approval result: #{outcome}"
      session.append_transcript({ "role" => "assistant", "content" => message })
      ActionCable.server.broadcast("session_#{session.id}", { type: "notice", content: message })
    rescue StandardError => e
      Rails.logger.warn("[Approvals::RunConnectorCall] could not note result in session: #{e.message}")
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
