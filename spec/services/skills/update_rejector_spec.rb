# frozen_string_literal: true

require "rails_helper"

RSpec.describe Skills::UpdateRejector, type: :service do
  let(:agent)    { create(:agent) }
  let(:admin_id) { 99 }
  let(:skill)    { create(:skill, name: "target_skill", content: "Current content.") }
  let(:proposal) do
    create(:skill_update_proposal,
      skill: skill,
      proposed_by_agent: agent,
      original_content: skill.content,
      proposed_content: "Proposed update.",
      status: "pending"
    )
  end

  describe ".call" do
    it "returns success" do
      result = described_class.call(proposal: proposal, rejected_by: admin_id)
      expect(result).to be_success
    end

    it "marks the proposal as rejected" do
      described_class.call(proposal: proposal, rejected_by: admin_id)
      expect(proposal.reload.status).to eq("rejected")
    end

    it "sets reviewed_by and reviewed_at" do
      described_class.call(proposal: proposal, rejected_by: admin_id)
      p = proposal.reload
      expect(p.reviewed_by_user_id).to eq(admin_id)
      expect(p.reviewed_at).to be_present
    end

    it "does not modify the skill content" do
      original = skill.content
      described_class.call(proposal: proposal, rejected_by: admin_id)
      expect(skill.reload.content).to eq(original)
    end

    it "stores rejection notes" do
      described_class.call(proposal: proposal, rejected_by: admin_id, notes: "Not an improvement")
      expect(proposal.reload.review_notes).to eq("Not an improvement")
    end

    context "when proposal is not pending" do
      before { proposal.update!(status: "approved", reviewed_at: 1.hour.ago, reviewed_by_user_id: 1) }

      it "returns failure" do
        result = described_class.call(proposal: proposal, rejected_by: admin_id)
        expect(result).not_to be_success
        expect(result.error).to include("not pending")
      end
    end
  end
end
