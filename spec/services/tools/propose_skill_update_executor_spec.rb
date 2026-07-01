# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::ProposeSkillUpdateExecutor, type: :service do
  let(:agent) { create(:agent) }
  let(:skill) { create(:skill, name: "my_skill", content: "Original instructions.") }
  let(:config) { {} }

  let(:valid_input) do
    {
      "skill_name"       => skill.name,
      "proposed_content" => "Updated instructions with improvements.",
      "rationale"        => "Found a better approach for the edge case."
    }
  end

  subject { described_class.new(input: valid_input, config: config, agent: agent) }

  describe "#call" do
    it "returns success for valid input" do
      expect(subject.call).to be_success
    end

    it "creates a SkillUpdateProposal" do
      expect { subject.call }.to change(SkillUpdateProposal, :count).by(1)
    end

    it "returns failure when skill_name is missing" do
      result = described_class.new(
        input: valid_input.merge("skill_name" => ""),
        config: config,
        agent: agent
      ).call
      expect(result).not_to be_success
    end

    it "returns failure when proposed_content is missing" do
      result = described_class.new(
        input: valid_input.merge("proposed_content" => ""),
        config: config,
        agent: agent
      ).call
      expect(result).not_to be_success
    end

    it "returns failure when rationale is missing" do
      result = described_class.new(
        input: valid_input.merge("rationale" => ""),
        config: config,
        agent: agent
      ).call
      expect(result).not_to be_success
    end
  end
end
