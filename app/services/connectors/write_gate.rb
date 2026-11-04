# frozen_string_literal: true

module Connectors
  # Holds a connector write for human approval instead of running it. The call is
  # stored as an ApprovalRequest and replayed by Approvals::RunConnectorCall once
  # a person approves it.
  class WriteGate
    ACTION = "connector_call"

    # @param tool [Tool, SystemTool]
    # @return [Boolean] true when +tool+ is a connector operation that changes data
    def self.hold?(tool)
      tool.is_a?(Connectors::ToolProxy) && !tool.read_only?
    end

    # @param tool [Connectors::ToolProxy]
    # @param input [Hash] arguments the model passed
    # @param agent [Agent]
    # @param session [Session, nil] chat session to report the outcome to
    # @return [ServiceResponse] success telling the model the call is waiting, or failure
    def self.call(tool:, input:, agent:, session: nil)
      new(tool:, input:, agent:, session:).call
    end

    def initialize(tool:, input:, agent:, session: nil)
      @tool = tool
      @input = input
      @agent = agent
      @session = session
    end

    def call
      return ServiceResponse.failure(error: "A write needs an agent to request approval for") unless @agent

      result = Approvals::Request.call(agent: @agent, action: ACTION, resource: resource, params: params)
      return ServiceResponse.failure(error: "Could not request approval: #{Array(result.error).join(', ')}") unless result.success?

      ServiceResponse.success(data: { output: waiting_message(result.data[:approval]), exit_code: 0 })
    end

    private

    def resource
      "Connector##{@tool.connector_id}/#{@tool.operation_name}"
    end

    def params
      {
        connector_id: @tool.connector_id,
        connector_name: @tool.connector_name,
        operation: @tool.operation_name,
        method: @tool.http_method,
        path: @tool.path,
        session_id: @session&.id,
        arguments: @input.is_a?(Hash) ? @input : {}
      }
    end

    def waiting_message(approval)
      "Not run yet. #{@tool.http_method} #{@tool.path} on #{@tool.connector_name} changes data, so it is waiting " \
        "for a person to approve it (approval ##{approval.id}). Tell the user, and do not retry."
    end
  end
end
