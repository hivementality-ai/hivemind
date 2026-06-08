# frozen_string_literal: true

require "rails_helper"

RSpec.describe SkillUpdateProposal, type: :model do
  let(:skill) { create(:skill, content: "Current content") }
  let(:agent) { create(:agent) }

  describe "validations" do
    subject do
      build(:skill_update_proposal,
        skill: skill,
        proposed_by_agent: agent,
        proposed_content: "New content",
        original_content: "Current content",
        rationale: "Better approach"
      )
    end

    it { is_expected.to be_valid }

    it "requires proposed_content" do
      subject.proposed_content = nil
      expect(subject).not_to be_valid
    end

    it "requires rationale" do
      subject.rationale = nil
      expect(subject).not_to be_valid
    end

    it "requires original_content" do
      subject.original_content = nil
      expect(subject).not_to be_valid
    end

    it "validates status inclusion" do
      subject.status = "bogus"
      expect(subject).not_to be_valid
    end
  end

  describe "#pending? / #approved? / #rejected?" do
    it "returns true for correct status" do
      expect(build(:skill_update_proposal, status: "pending")).to be_pending
      expect(build(:skill_update_proposal, :approved)).to be_approved
      expect(build(:skill_update_proposal, :rejected)).to be_rejected
    end
  end

  describe "#stale?" do
    it "is stale when skill content has changed since proposal" do
      proposal = create(:skill_update_proposal, skill: skill, original_content: "Old content")
      skill.update_column(:content, "New different content")
      expect(proposal.stale?).to be true
    end

    it "is not stale when skill content matches original" do
      proposal = create(:skill_update_proposal, skill: skill, original_content: skill.content)
      expect(proposal.stale?).to be false
    end
  end

  describe "scopes" do
    let!(:pending_p)  { create(:skill_update_proposal, skill: skill, proposed_by_agent: agent) }
    let!(:approved_p) { create(:skill_update_proposal, :approved, skill: skill, proposed_by_agent: agent) }
    let!(:rejected_p) { create(:skill_update_proposal, :rejected, skill: skill, proposed_by_agent: agent) }

    it "pending scope returns only pending" do
      expect(described_class.pending).to contain_exactly(pending_p)
    end

    it "approved scope returns only approved" do
      expect(described_class.approved).to contain_exactly(approved_p)
    end

    it "rejected scope returns only rejected" do
      expect(described_class.rejected).to contain_exactly(rejected_p)
    end
  end
end
