# frozen_string_literal: true

require "rails_helper"

RSpec.describe Skill, type: :model do
  subject { build(:skill) }

  describe "associations" do
    it { should have_many(:agent_skills).dependent(:destroy) }
    it { should have_many(:agents).through(:agent_skills) }
    it { should have_many(:skill_tools).dependent(:destroy) }
    it { should have_many(:tools).through(:skill_tools) }
  end

  describe "validations" do
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name) }
    it { should validate_presence_of(:content) }
  end

  describe "scopes" do
    let!(:enabled) { create(:skill, enabled: true) }
    let!(:disabled) { create(:skill, enabled: false) }
    let!(:builtin) { create(:skill, builtin: true) }
    let!(:custom) { create(:skill, builtin: false) }

    it ".enabled returns enabled skills" do
      expect(Skill.enabled).to include(enabled, builtin, custom)
      expect(Skill.enabled).not_to include(disabled)
    end

    it ".builtin returns builtin skills" do
      expect(Skill.builtin).to include(builtin)
    end

    it ".custom returns non-builtin skills" do
      expect(Skill.custom).not_to include(builtin)
    end
  end

  describe ".from_skill_md" do
    context "with frontmatter" do
      let(:text) do
        <<~MD
          ---
          name: My Skill
          description: Does things
          category: coding
          ---
          The actual content here.
        MD
      end

      it "parses name from frontmatter" do
        skill = Skill.from_skill_md(text)
        expect(skill.name).to eq("My Skill")
      end

      it "parses description" do
        skill = Skill.from_skill_md(text)
        expect(skill.description).to eq("Does things")
      end

      it "parses category" do
        skill = Skill.from_skill_md(text)
        expect(skill.category).to eq("coding")
      end

      it "parses content from body" do
        skill = Skill.from_skill_md(text)
        expect(skill.content).to eq("The actual content here.")
      end
    end

    context "with nested openclaw category" do
      let(:text) do
        <<~MD
          ---
          name: Nested
          metadata:
            openclaw:
              category: automation
          ---
          Body
        MD
      end

      it "extracts nested category" do
        skill = Skill.from_skill_md(text)
        expect(skill.category).to eq("automation")
      end
    end

    context "without frontmatter" do
      it "returns nil name and uses full text as content" do
        skill = Skill.from_skill_md("Just plain text")
        expect(skill.name).to be_nil
        expect(skill.content).to eq("Just plain text")
      end
    end
  end

  describe "#to_skill_md" do
    let(:skill) { build(:skill, name: "Export Test", description: "A desc", category: "utilities", content: "Skill body here") }

    it "generates valid SKILL.md format" do
      md = skill.to_skill_md
      expect(md).to include("---")
      expect(md).to include("name: Export Test")
      expect(md).to include("description: A desc")
      expect(md).to include("category: utilities")
      expect(md).to include("Skill body here")
    end

    it "omits description when blank" do
      skill.description = nil
      md = skill.to_skill_md
      expect(md).not_to include("description:")
    end

    it "omits category when blank" do
      skill.category = nil
      md = skill.to_skill_md
      expect(md).not_to include("category:")
    end
  end
end
