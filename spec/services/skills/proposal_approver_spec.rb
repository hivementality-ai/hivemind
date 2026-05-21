# frozen_string_literal: true

require "rails_helper"

RSpec.describe Skills::ProposalApprover, type: :service do
  let(:team)  { create(:team) }
  let(:agent) { create(:agent, team: team) }
  let(:admin_user_id) { 42 }

  let(:pending_skill) do
    create(:skill,
      name: "my_proposal",
      source: "agent",
      enabled: false,
      proposal_status: "pending",
      proposed_by_agent_id: agent.id,
      proposed_at: 1.hour.ago,
      metadata: {
        "created_by_agent_id" => agent.id,
        "share_with_team" => false
      }
    )
  end

  describe ".call" do
    context "with a pending skill" do
      it "enables the skill" do
        described_class.call(skill: pending_skill, approved_by: admin_user_id)
        expect(pending_skill.reload.enabled).to be true
      end

      it "sets proposal_status to approved" do
        described_class.call(skill: pending_skill, approved_by: admin_user_id)
        expect(pending_skill.reload.proposal_status).to eq("approved")
      end

      it "sets approved_at and approved_by" do
        described_class.call(skill: pending_skill, approved_by: admin_user_id)
        skill = pending_skill.reload
        expect(skill.approved_at).to be_present
        expect(skill.approved_by).to eq(admin_user_id)
      end

      it "returns success" do
        result = described_class.call(skill: pending_skill, approved_by: admin_user_id)
        expect(result).to be_success
      end

      it "assigns the skill to the proposing agent" do
        described_class.call(skill: pending_skill, approved_by: admin_user_id)
        expect(AgentSkill.exists?(agent: agent, skill: pending_skill)).to be true
      end

      it "resolves the open ApprovalRequest" do
        approval = create(:approval_request,
          agent: agent,
          action: "create_skill",
          resource: "Skill##{pending_skill.id}",
          status: "pending"
        )

        described_class.call(skill: pending_skill, approved_by: admin_user_id, notes: "Looks good")

        expect(approval.reload.status).to eq("approved")
        expect(approval.reload.resolution_notes).to eq("Looks good")
      end
    end

    context "when skill is not pending" do
      it "returns failure for an already-approved skill" do
        pending_skill.update!(proposal_status: "approved")
        result = described_class.call(skill: pending_skill, approved_by: admin_user_id)
        expect(result).not_to be_success
        expect(result.error).to include("not a pending proposal")
      end

      it "returns failure for a rejected skill" do
        pending_skill.update!(proposal_status: "rejected")
        result = described_class.call(skill: pending_skill, approved_by: admin_user_id)
        expect(result).not_to be_success
      end
    end

    context "team sharing" do
      let(:teammate) { create(:agent, team: team) }

      before { teammate }

      it "shares with team when metadata flag is set" do
        pending_skill.update!(metadata: pending_skill.metadata.merge("share_with_team" => true))
        described_class.call(skill: pending_skill, approved_by: admin_user_id)
        expect(AgentSkill.exists?(agent: teammate, skill: pending_skill)).to be true
      end

      it "does not share with team when flag is false" do
        described_class.call(skill: pending_skill, approved_by: admin_user_id)
        expect(AgentSkill.exists?(agent: teammate, skill: pending_skill)).to be false
      end
    end
  end
end
