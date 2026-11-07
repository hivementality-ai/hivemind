# frozen_string_literal: true

module Approvals
  # Runs a held tool call once its approval is granted, with the arguments stored on the request
  # (as edited by the approver, if they edited). The outcome goes to the audit log, back to the
  # approver, and into the chat session that asked for the call.
  class RunToolCall
    MAX_OUTCOME_CHARS = 300

    # @param approval [ApprovalRequest] an approved "tool_call" request
    # @return [ServiceResponse] success carrying +data[:outcome]+ and +data[:succeeded]+
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
      tool = Tool.find_by(id: params["tool_id"])
      return ServiceResponse.failure(error: "Tool #{params['tool_name']} no longer exists") unless tool
      return ServiceResponse.failure(error: "Tool #{tool.name} is disabled") unless tool.enabled?

      session = Session.find_by(id: params["session_id"])
      return ServiceResponse.failure(error: "The chat this came from is gone") unless session

      @ran = true
      Tools::Executor.call(tool: tool, input: params["arguments"] || {}, agent: @approval.agent, session: session, approved: true)
    end

    def params
      @approval.params || {}
    end

    def label
      CardFields.new(@approval).verb
    end

    def outcome_line(result)
      return "Did not #{label}: #{result.error}" unless @ran
      return "Ran: #{label}. It worked#{detail(result.data[:output])}" if result.success?

      "Tried to #{label} but it failed: #{result.error.to_s.truncate(MAX_OUTCOME_CHARS)}"
    end

    def detail(output)
      text = output.to_s.strip
      text.empty? ? "" : " (#{text.truncate(MAX_OUTCOME_CHARS)})"
    end

    def notify_session(outcome)
      return if params["session_id"].blank?

      ApprovalSessionNoteJob.perform_later(params["session_id"], "Approval result: #{outcome}")
    rescue StandardError => e
      Rails.logger.warn("[Approvals::RunToolCall] could not note result in session: #{e.message}")
    end

    def record(result)
      AuditLog.create(
        actor_type: "Agent",
        actor_id: @approval.agent_id,
        action: "tool_call_executed",
        resource: "ApprovalRequest##{@approval.id}",
        metadata: {
          tool: params["tool_name"],
          edited: params["edited"] == true,
          success: result.success?
        }
      )
    end
  end
end
