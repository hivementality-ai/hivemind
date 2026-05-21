# frozen_string_literal: true

require "rails_helper"

RSpec.describe Skills::ProposalRejector, type: :service do
  let(:team)  { create(:team) }
  let(:agent) { create(:agent, team: team) }
  let(:admin_user_id) { 99 }

  let(:pending_skill) do
    create(:skill,
      name: "bad_proposal",
      source: "agent",
      enabled: false,
      proposal_status: "pending",
      proposed_by_agent_id: agent.id,
      proposed_at: 2.hours.ago
    )
  end

  describe ".call" do
    context "with a pending skill" do
      it "returns success" do
        result = described_class.call(skill: pending_skill, rejected_by: admin_user_id)
        expect(result).to be_success
      end

      it "sets proposal_status to rejected" do
        described_class.call(skill: pending_skill, rejected_by: admin_user_id)
        expect(pending_skill.reload.proposal_status).to eq("rejected")
      end

      it "keeps the skill disabled" do
        described_class.call(skill: pending_skill, rejected_by: admin_user_id)
        expect(pending_skill.reload.enabled).to be false
      end

      it "sets rejection metadata" do
        described_class.call(skill: pending_skill, rejected_by: admin_user_id, notes: "Too vague")
        skill = pending_skill.reload
        expect(skill.proposal_rejected_at).to be_present
        expect(skill.proposal_rejected_by).to eq(admin_user_id)
        expect(skill.proposal_notes).to eq("Too vague")
      end

      it "resolves the open ApprovalRequest as rejected" do
        approval = create(:approval_request,
          agent: agent,
          action: "create_skill",
          resource: "Skill##{pending_skill.id}",
          status: "pending"
        )

        described_class.call(skill: pending_skill, rejected_by: admin_user_id, notes: "Not useful")

        expect(approval.reload.status).to eq("rejected")
        expect(approval.reload.resolution_notes).to eq("Not useful")
      end

      it "does not assign the skill to the agent" do
        described_class.call(skill: pending_skill, rejected_by: admin_user_id)
        expect(AgentSkill.exists?(agent: agent, skill: pending_skill)).to be false
      end
    end

    context "when skill is not pending" do
      it "returns failure for an already-approved skill" do
        pending_skill.update!(proposal_status: "approved", enabled: true)
        result = described_class.call(skill: pending_skill, rejected_by: admin_user_id)
        expect(result).not_to be_success
        expect(result.error).to include("not a pending proposal")
      end

      it "returns failure for an already-rejected skill" do
        pending_skill.update!(proposal_status: "rejected")
        result = described_class.call(skill: pending_skill, rejected_by: admin_user_id)
        expect(result).not_to be_success
      end
    end
  end
end
