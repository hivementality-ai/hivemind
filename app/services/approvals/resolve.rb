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
      Rails.logger.info("Executing approved action: #{approval.action} on #{approval.resource}")

      case approval.action
      when "create_skill"
        activate_skill(approval)
      when "create_tool"
        activate_tool(approval)
      end
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
