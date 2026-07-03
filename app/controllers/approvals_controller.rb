# frozen_string_literal: true

class ApprovalsController < ApplicationController
  before_action :authorize_admin_or_owner!

  VAULT_NS = Vault::WriteConfirmation::REDIS_NAMESPACE

  def index
    @approval_requests = ApprovalRequest.pending.not_expired
                                        .includes(:agent)
                                        .order(requested_at: :desc)
                                        .limit(50)

    @vault_confirmations = pending_vault_confirmations

    @skill_update_proposals = SkillUpdateProposal.pending
                                                 .includes(:skill, :proposed_by_agent)
                                                 .recent
                                                 .limit(50)
  end

  def approve
    case params[:approval_type]
    when "approval_request"
      result = Approvals::Resolve.call(
        approval_id: params[:id],
        decision: "approved",
        resolved_by: current_user.id
      )
      set_flash(result, ok: "Approval request approved.", err: result.error)
    when "vault_confirmation"
      pending = retrieve_vault_pending(params[:id])
      if pending
        agent = Agent.find_by(id: pending["agent_id"])
        Vault::WriteConfirmation.confirm_write(confirmation_id: params[:id], agent: agent)
        flash[:notice] = "Vault write confirmed."
      else
        flash[:alert] = "Confirmation expired or not found."
      end
    when "skill_update_proposal"
      proposal = SkillUpdateProposal.find(params[:id])
      result = Skills::UpdateApprover.call(proposal:, approved_by: current_user.id)
      set_flash(result, ok: "Skill update approved.", err: result.error)
    else
      flash[:alert] = "Unknown approval type."
    end
    redirect_to approvals_path
  end

  def reject
    case params[:approval_type]
    when "approval_request"
      result = Approvals::Resolve.call(
        approval_id: params[:id],
        decision: "rejected",
        resolved_by: current_user.id
      )
      set_flash(result, ok: "Approval request rejected.", err: result.error)
    when "vault_confirmation"
      delete_vault_pending(params[:id])
      flash[:notice] = "Vault write rejected."
    when "skill_update_proposal"
      proposal = SkillUpdateProposal.find(params[:id])
      result = Skills::UpdateRejector.call(proposal:, rejected_by: current_user.id)
      set_flash(result, ok: "Skill update proposal rejected.", err: result.error)
    else
      flash[:alert] = "Unknown approval type."
    end
    redirect_to approvals_path
  end

  private

  def pending_vault_confirmations
    redis = Redis.current
    keys = redis.keys("#{VAULT_NS}:*")
    keys.filter_map do |key|
      data = redis.get(key)
      next unless data

      parsed = JSON.parse(data)
      ttl = redis.ttl(key)
      parsed.merge("confirmation_id" => key.delete_prefix("#{VAULT_NS}:"), "expires_in" => ttl)
    end.sort_by { |c| c["confirmation_id"] }
  rescue StandardError => e
    Rails.logger.warn("ApprovalsController: failed to list vault confirmations: #{e.message}")
    []
  end

  def retrieve_vault_pending(confirmation_id)
    data = Redis.current.get("#{VAULT_NS}:#{confirmation_id}")
    data ? JSON.parse(data) : nil
  rescue StandardError
    nil
  end

  def delete_vault_pending(confirmation_id)
    Redis.current.del("#{VAULT_NS}:#{confirmation_id}")
  rescue StandardError => e
    Rails.logger.warn("ApprovalsController: failed to delete vault confirmation: #{e.message}")
  end

  def set_flash(result, ok:, err:)
    if result.success?
      flash[:notice] = ok
    else
      flash[:alert] = err
    end
  end
end
