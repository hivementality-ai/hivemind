# frozen_string_literal: true

# Buttons on the approval card that appears in chat. Each answers with a Turbo stream that
# swaps the card for its new state, so the page does not reload.
class ApprovalCardsController < ApplicationController
  before_action :authorize_admin_or_owner!
  before_action :set_approval

  def approve
    resolve("approved")
  end

  def approve_with_edits
    resolve("approved", edits: params[:edits]&.to_unsafe_h)
  end

  def decline
    resolve("rejected")
  end

  private

  def set_approval
    @approval = ApprovalRequest.find_by(id: params[:id], action: Approvals::ToolCallGate::ACTION)
    head :not_found unless @approval
  end

  def resolve(decision, edits: nil)
    result = Approvals::Resolve.call(approval_id: @approval.id, decision: decision, resolved_by: current_user.id, edits: edits)
    @approval.reload
    @outcome = result.success? ? result.data[:outcome] : result.error
    @failed = !result.success?

    respond_to do |format|
      format.turbo_stream { render :resolved }
      format.html { redirect_back fallback_location: approvals_path, notice: @outcome }
    end
  end
end
