# frozen_string_literal: true

require "rails_helper"

RSpec.describe Skills::UpdateProposer, type: :service do
  let(:agent) { create(:agent) }
  let(:skill) { create(:skill, name: "my_skill", content: "Original content here.") }

  let(:valid_params) do
    {
      agent: agent,
      skill_name: skill.name,
      proposed_content: "Updated content with improvements.",
      rationale: "Added missing edge case for nil input."
    }
  end

  describe ".call" do
    it "returns success for a valid proposal" do
      result = described_class.call(**valid_params)
      expect(result).to be_success
    end

    it "creates a SkillUpdateProposal record" do
      expect { described_class.call(**valid_params) }
        .to change(SkillUpdateProposal, :count).by(1)
    end

    it "stores the proposed and original content" do
      described_class.call(**valid_params)
      proposal = SkillUpdateProposal.last
      expect(proposal.proposed_content).to eq("Updated content with improvements.")
      expect(proposal.original_content).to eq(skill.content)
    end

    it "stores the rationale" do
      described_class.call(**valid_params)
      expect(SkillUpdateProposal.last.rationale).to eq("Added missing edge case for nil input.")
    end

    it "sets status to pending" do
      described_class.call(**valid_params)
      expect(SkillUpdateProposal.last.status).to eq("pending")
    end

    it "links proposal to the proposing agent" do
      described_class.call(**valid_params)
      expect(SkillUpdateProposal.last.proposed_by_agent).to eq(agent)
    end

    it "returns the proposal_id in data" do
      result = described_class.call(**valid_params)
      expect(result.data[:proposal_id]).to be_present
    end

    context "when skill does not exist" do
      it "returns failure" do
        result = described_class.call(**valid_params.merge(skill_name: "nonexistent_skill"))
        expect(result).not_to be_success
        expect(result.error).to include("not found")
      end
    end

    context "when proposed content is blank" do
      it "returns failure" do
        result = described_class.call(**valid_params.merge(proposed_content: ""))
        expect(result).not_to be_success
        expect(result.error).to include("blank")
      end
    end

    context "when rationale is blank" do
      it "returns failure" do
        result = described_class.call(**valid_params.merge(rationale: ""))
        expect(result).not_to be_success
        expect(result.error).to include("Rationale")
      end
    end

    context "when proposed content is identical to current" do
      it "returns failure" do
        result = described_class.call(**valid_params.merge(proposed_content: skill.content))
        expect(result).not_to be_success
        expect(result.error).to include("identical")
      end
    end

    context "when a pending proposal already exists" do
      before { create(:skill_update_proposal, skill: skill, proposed_by_agent: agent) }

      it "returns failure" do
        result = described_class.call(**valid_params)
        expect(result).not_to be_success
        expect(result.error).to include("already has a pending")
      end
    end

    context "when proposed content exceeds max length" do
      it "returns failure" do
        result = described_class.call(**valid_params.merge(proposed_content: "x" * 50_001))
        expect(result).not_to be_success
        expect(result.error).to include("maximum length")
      end
    end
  end
end
