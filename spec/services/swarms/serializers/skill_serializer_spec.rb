# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Serializers::SkillSerializer do
  describe ".call" do
    it "includes name" do
      skill = build(:skill, name: "git-workflow")
      result = described_class.call(skill: skill)
      expect(result["name"]).to eq("git-workflow")
    end

    it "includes summary when present" do
      skill = build(:skill, name: "git-workflow", summary: "Git workflow automation")
      result = described_class.call(skill: skill)
      expect(result["summary"]).to eq("Git workflow automation")
    end

    it "includes description when present" do
      skill = build(:skill, name: "git-workflow", description: "Automates git operations")
      result = described_class.call(skill: skill)
      expect(result["description"]).to eq("Automates git operations")
    end

    it "includes content inline" do
      skill = build(:skill, name: "git-workflow", content: "# Git Workflow\nUse git properly.")
      result = described_class.call(skill: skill)
      expect(result["content"]).to eq("# Git Workflow\nUse git properly.")
    end

    it "includes category when present" do
      skill = build(:skill, name: "git-workflow", category: "coding")
      result = described_class.call(skill: skill)
      expect(result["category"]).to eq("coding")
    end

    it "omits summary when blank" do
      skill = build(:skill, name: "git-workflow", summary: nil)
      # summary has a presence validation so we force it blank here for the test
      skill.instance_variable_set(:@summary, nil)
      allow(skill).to receive(:summary).and_return(nil)
      result = described_class.call(skill: skill)
      expect(result).not_to have_key("summary")
    end

    it "omits description when blank" do
      skill = build(:skill, name: "git-workflow", description: nil)
      result = described_class.call(skill: skill)
      expect(result).not_to have_key("description")
    end

    it "omits category when blank" do
      skill = build(:skill, name: "git-workflow", category: nil)
      result = described_class.call(skill: skill)
      expect(result).not_to have_key("category")
    end

    it "returns a Hash" do
      skill = build(:skill, name: "git-workflow")
      expect(described_class.call(skill: skill)).to be_a(Hash)
    end

    it "produces output that is valid against SwarmSchema skills section" do
      skill = build(:skill,
        name:        "my-skill",
        summary:     "A test skill summary",
        description: "Does stuff",
        content:     "# My Skill\n\nContent here.",
        category:    "utilities"
      )
      result = described_class.call(skill: skill)

      raw = { "swarm_version" => "1.0", "name" => "Test", "skills" => [ result ] }
      validation = Swarms::SwarmSchema.validate(raw)
      expect(validation).to be_valid
    end
  end
end
