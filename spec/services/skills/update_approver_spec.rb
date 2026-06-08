# frozen_string_literal: true

require "rails_helper"

RSpec.describe Skills::UpdateApprover, type: :service do
  let(:agent)        { create(:agent) }
  let(:admin_id)     { 42 }
  let(:skill)        { create(:skill, name: "target_skill", content: "Old content.") }
  let(:proposal) do
    create(:skill_update_proposal,
      skill: skill,
      proposed_by_agent: agent,
      original_content: skill.content,
      proposed_content: "New improved content.",
      status: "pending"
    )
  end

  describe ".call" do
    it "returns success" do
      result = described_class.call(proposal: proposal, approved_by: admin_id)
      expect(result).to be_success
    end

    it "applies the proposed content to the skill" do
      described_class.call(proposal: proposal, approved_by: admin_id)
      expect(skill.reload.content).to eq("New improved content.")
    end

    it "marks the proposal as approved" do
      described_class.call(proposal: proposal, approved_by: admin_id)
      expect(proposal.reload.status).to eq("approved")
    end

    it "sets reviewed_by and reviewed_at on the proposal" do
      described_class.call(proposal: proposal, approved_by: admin_id)
      p = proposal.reload
      expect(p.reviewed_by_user_id).to eq(admin_id)
      expect(p.reviewed_at).to be_present
    end

    it "creates a SkillVersion snapshot for the update" do
      expect { described_class.call(proposal: proposal, approved_by: admin_id) }
        .to change { skill.skill_versions.count }.by(1)
    end

    it "records the version with change_source agent_update" do
      described_class.call(proposal: proposal, approved_by: admin_id)
      version = skill.skill_versions.order(version_number: :desc).first
      expect(version.change_source).to eq("agent_update")
    end

    it "links the version to the proposal" do
      described_class.call(proposal: proposal, approved_by: admin_id)
      version = skill.skill_versions.order(version_number: :desc).first
      expect(version.update_proposal_id).to eq(proposal.id)
    end

    it "stores optional review notes" do
      described_class.call(proposal: proposal, approved_by: admin_id, notes: "Excellent improvement")
      expect(proposal.reload.review_notes).to eq("Excellent improvement")
    end

    context "when proposal is not pending" do
      before { proposal.update!(status: "rejected", reviewed_at: 1.hour.ago, reviewed_by_user_id: 1) }

      it "returns failure" do
        result = described_class.call(proposal: proposal, approved_by: admin_id)
        expect(result).not_to be_success
        expect(result.error).to include("not pending")
      end

      it "does not modify skill content" do
        original = skill.content
        described_class.call(proposal: proposal, approved_by: admin_id)
        expect(skill.reload.content).to eq(original)
      end
    end
  end
end
