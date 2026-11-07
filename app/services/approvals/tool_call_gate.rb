# frozen_string_literal: true

module Approvals
  # Holds a tool call that leaves the house (email, channel post, file delete, a write to an outside
  # service) as a pending approval instead of running it. The exact arguments are stored and replayed
  # by Approvals::RunToolCall once a person approves, so nothing is regenerated.
  #
  # The call never blocks: the model gets a short "waiting" result and carries on, so an unattended
  # run always finishes. A scheduled task or watch that was set up with sending allowed skips the
  # card and runs the action directly.
  class ToolCallGate
    ACTION = "tool_call"

    # @param tool [Tool, SystemTool]
    # @param input [Hash] arguments the model passed
    # @param agent [Agent, nil]
    # @param session [Session, nil]
    # @return [String, nil] the AskFirst category when the call must wait for a person, else nil
    def self.category_to_hold(tool:, input:, agent:, session:)
      return if tool.is_a?(SystemTool)

      category = AskFirst.category_to_ask(agent:, executor_type: tool.executor_type, input:)
      return unless category
      return if sending_allowed?(session)

      category
    end

    # @param session [Session, nil]
    # @return [Boolean] true when a scheduled task or watch run was set up with sending allowed
    def self.sending_allowed?(session)
      return false unless unattended?(session)

      task_id = session&.metadata&.dig("scheduled_task_id")
      task_id.present? && ScheduledTask.where(id: task_id, allow_sending: true).exists?
    end

    # @param session [Session, nil]
    # @return [Boolean] true when no person is watching this run (scheduled task, watch, or no chat at all)
    def self.unattended?(session)
      session.nil? || session.metadata&.dig("type") == "scheduled"
    end

    # @param tool [Tool]
    # @param input [Hash]
    # @param agent [Agent]
    # @param session [Session, nil]
    # @param category [String] an AskFirst category
    # @return [ServiceResponse] success telling the model the action is waiting, or failure
    def self.call(tool:, input:, agent:, session:, category:)
      new(tool:, input:, agent:, session:, category:).call
    end

    def initialize(tool:, input:, agent:, session:, category:)
      @tool = tool
      @input = input.is_a?(Hash) ? input.deep_stringify_keys : {}
      @agent = agent
      @session = session
      @category = category
    end

    def call
      return ServiceResponse.failure(error: "This action needs an agent to ask for approval") unless @agent

      result = Request.call(agent: @agent, action: ACTION, resource: "Tool##{@tool.name}", params: params)
      return ServiceResponse.failure(error: "Could not ask for approval: #{Array(result.error).join(', ')}") unless result.success?

      approval = result.data[:approval]
      broadcast_card(approval)
      ServiceResponse.success(data: { output: waiting_message(approval), exit_code: 0 })
    end

    private

    def params
      {
        tool_id: (@tool.id if @tool.is_a?(Tool) && @tool.persisted?),
        tool_name: @tool.name,
        category: @category,
        session_id: @session&.id,
        unattended: self.class.unattended?(@session),
        arguments: @input
      }
    end

    def broadcast_card(approval)
      return unless @session

      Turbo::StreamsChannel.broadcast_append_to(
        CardStream.stream_name(@session),
        target: CardStream.container_id(@session),
        partial: "approvals/card",
        locals: { approval: approval }
      )
    rescue StandardError => e
      Rails.logger.warn("[Approvals::ToolCallGate] could not show the card: #{e.message}")
    end

    def waiting_message(approval)
      verb = CardFields.new(approval).verb
      if self.class.unattended?(@session)
        "Not done. Nobody is watching this run, so the request to #{verb} was held for approval instead " \
          "(approval ##{approval.id}). Finish what you can, and say clearly in your final answer that this action " \
          "is waiting for the user to approve it."
      else
        "Not done yet. The request to #{verb} is waiting for the user's OK (approval ##{approval.id}, a card is " \
          "showing in the chat). Carry on without it and do not retry; you will be told what they decide."
      end
    end
  end
end
