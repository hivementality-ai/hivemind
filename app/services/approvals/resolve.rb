# frozen_string_literal: true

module Approvals
  class Resolve
    # @param approval_id [Integer]
    # @param decision [String] "approved" or "rejected"
    # @param resolved_by [Integer, String] who decided
    # @param notes [String, nil]
    # @param edits [Hash{String => String}, nil] changed fields for a held tool call; run instead of the original
    def self.call(approval_id:, decision:, resolved_by:, notes: nil, edits: nil)
      new(approval_id:, decision:, resolved_by:, notes:, edits:).call
    end

    def initialize(approval_id:, decision:, resolved_by:, notes: nil, edits: nil)
      @approval_id = approval_id
      @decision = decision
      @resolved_by = resolved_by
      @notes = notes
      @edits = edits
    end

    # The decision is recorded under a row lock, so a double click or a second tab sees the request
    # already resolved and nothing runs twice.
    def call
      approval = ApprovalRequest.find_by(id: @approval_id)
      return ServiceResponse.failure(error: "Approval request not found") unless approval

      failure = approval.with_lock { record_decision(approval) }
      return failure if failure

      broadcast_resolution(approval)
      log_audit(approval)
      WebhookEmitter.emit(
        "approval.resolved",
        { approval_id: approval.id, status: approval.status, action: approval.action, resource: approval.resource },
        agent: approval.agent, team: approval.agent&.team
      )
      ran = run_connector_call(approval) if @decision == "approved" && approval.action == "connector_call"
      ran = run_tool_call(approval) if @decision == "approved" && approval.action == ToolCallGate::ACTION
      note_decline(approval) if @decision == "rejected" && approval.action == ToolCallGate::ACTION
      execute_pending_action(approval) if @decision == "approved"

      ServiceResponse.success(data: { approval:, outcome: ran&.dig(:outcome), outcome_ok: ran&.dig(:succeeded) })
    rescue StandardError => e
      ServiceResponse.failure(error: "Resolution failed: #{e.message}")
    end

    private

    # @return [ServiceResponse, nil] a failure when the request cannot be decided, else nil once saved
    def record_decision(approval)
      return ServiceResponse.failure(error: "Approval request already resolved") unless approval.pending?
      return ServiceResponse.failure(error: "Approval request expired") if approval.expired?
      return ServiceResponse.failure(error: "Invalid decision") unless %w[approved rejected].include?(@decision)

      params = edited_params(approval)
      return ServiceResponse.failure(error: "That change could not be used. Check the fields and try again.") unless params

      approval.update!(
        status: @decision,
        params: params,
        resolved_at: Time.current,
        resolved_by: @resolved_by,
        resolution_notes: @notes
      )
      nil
    end

    # @return [Hash, nil] the params to save; nil when the edits are not acceptable
    def edited_params(approval)
      return approval.params if @edits.blank? || @decision != "approved" || approval.action != ToolCallGate::ACTION

      arguments = CardFields.new(approval).edited_arguments(@edits)
      return unless arguments

      approval.params.merge("original_arguments" => approval.params["arguments"], "arguments" => arguments, "edited" => true)
    end

    def run_tool_call(approval)
      Approvals::RunToolCall.call(approval: approval).data
    end

    def note_decline(approval)
      return if approval.params["session_id"].blank?

      ApprovalSessionNoteJob.perform_later(
        approval.params["session_id"],
        "Approval result: The user declined to #{CardFields.new(approval).verb}. It was not done. Carry on without it."
      )
    end

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
        resource: "ApprovalRequest##{approval.id}",
        metadata: {
          original_action: approval.action,
          resource: approval.resource,
          params: approval.params,
          notes: @notes
        }
      )
    end

    def execute_pending_action(approval)
      Rails.logger.info("Executing approved action: #{approval.action} on #{approval.resource}")

      case approval.action
      when "create_skill"
        activate_skill(approval)
      when "create_tool"
        activate_tool(approval)
      when "create_connector"
        activate_connector(approval)
      when "update_connector"
        apply_connector_fix(approval)
      end
    end

    def run_connector_call(approval)
      Approvals::RunConnectorCall.call(approval: approval).data
    end

    def apply_connector_fix(approval)
      connector = Connector.find_by(id: approval.params["connector_id"])
      return unless connector

      connector.update!(operations: approval.params["operations"], base_url: approval.params["base_url_after"], health: {})
    end

    def activate_connector(approval)
      connector = Connector.find_by(id: approval.params["connector_id"])
      return unless connector&.pending_approval?

      connector.update!(enabled: true, pending_approval: false)
    end

    def activate_skill(approval)
      skill = Skill.find_by(id: approval.params["skill_id"])
      return unless skill

      skill.update!(enabled: true, approved_at: Time.current, approved_by: @resolved_by)

      agent = Agent.find_by(id: skill.metadata&.dig("created_by_agent_id"))
      if agent
        AgentSkill.find_or_create_by!(agent: agent, skill: skill)

        if skill.metadata&.dig("share_with_team") && agent.team
          agent.team.agents.where.not(id: agent.id).find_each do |teammate|
            AgentSkill.find_or_create_by!(agent: teammate, skill: skill)
          end
        end

        Agents::SyncSkillTools.call(agent: agent)
      end
    end

    def activate_tool(approval)
      tool = Tool.find_by(id: approval.params["tool_id"])
      return unless tool

      tool.update!(enabled: true)

      agent = Agent.find_by(id: tool.config&.dig("created_by_agent_id"))
      if agent
        AgentTool.find_or_create_by!(agent: agent, tool: tool)

        if tool.config&.dig("share_with_team") && agent.team
          agent.team.agents.where.not(id: agent.id).find_each do |teammate|
            AgentTool.find_or_create_by!(agent: teammate, tool: tool)
          end
        end
      end
    end
  end
end
