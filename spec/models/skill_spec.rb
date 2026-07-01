# frozen_string_literal: true

require "rails_helper"

RSpec.describe Skill, type: :model do
  subject { build(:skill) }

  describe "associations" do
    it { should have_many(:agent_skills).dependent(:destroy) }
    it { should have_many(:agents).through(:agent_skills) }
    it { should have_many(:skill_tools).dependent(:destroy) }
    it { should have_many(:tools).through(:skill_tools) }
    it { should have_many(:skill_load_events).dependent(:destroy) }
  end

  describe "validations" do
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name) }
    it { should validate_presence_of(:content) }
    it { should validate_inclusion_of(:tier).in_array(%w[core contextual manual]) }
  end

  describe "scopes" do
    let!(:enabled) { create(:skill, enabled: true) }
    let!(:disabled) { create(:skill, enabled: false) }
    let!(:builtin) { create(:skill, builtin: true) }
    let!(:custom) { create(:skill, builtin: false) }
    let!(:core_skill) { create(:skill, tier: "core") }
    let!(:contextual_skill) { create(:skill, tier: "contextual") }
    let!(:manual_skill) { create(:skill, tier: "manual") }

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

    it ".core_tier returns only core skills" do
      expect(Skill.core_tier).to include(core_skill)
      expect(Skill.core_tier).not_to include(contextual_skill, manual_skill)
    end

    it ".contextual_tier returns only contextual skills" do
      expect(Skill.contextual_tier).to include(contextual_skill)
      expect(Skill.contextual_tier).not_to include(core_skill, manual_skill)
    end

    it ".manual_tier returns only manual skills" do
      expect(Skill.manual_tier).to include(manual_skill)
      expect(Skill.manual_tier).not_to include(core_skill, contextual_skill)
    end

    it ".with_tag filters by tag" do
      tagged = create(:skill, tags: %w[github git])
      untagged = create(:skill, tags: [])
      expect(Skill.with_tag("github")).to include(tagged)
      expect(Skill.with_tag("github")).not_to include(untagged)
    end
  end

  describe "#tags" do
    it "returns empty array when nil" do
      skill = build(:skill)
      skill[:tags] = nil
      expect(skill.tags).to eq([])
    end

    it "returns the tags array" do
      skill = build(:skill, tags: %w[github pr])
      expect(skill.tags).to eq(%w[github pr])
    end
  end

  describe "#trigger_patterns" do
    it "returns empty array when nil" do
      skill = build(:skill)
      skill[:trigger_patterns] = nil
      expect(skill.trigger_patterns).to eq([])
    end

    it "returns the patterns array" do
      skill = build(:skill, trigger_patterns: ["open.*pr"])
      expect(skill.trigger_patterns).to eq(["open.*pr"])
    end
  end

  describe "#relevance_score_for" do
    it "delegates to Skills::RelevanceScorer" do
      skill = build(:skill, tags: %w[github], trigger_patterns: [])
      allow(Skills::RelevanceScorer).to receive(:score).and_return(0.75)
      score = skill.relevance_score_for("open a pr on github")
      expect(Skills::RelevanceScorer).to have_received(:score).with(skill: skill, context: "open a pr on github")
      expect(score).to eq(0.75)
    end

    it "returns 0.0 for blank context" do
      skill = build(:skill, tags: %w[github])
      expect(skill.relevance_score_for("")).to eq(0.0)
    end

    it "returns 0.0 when no tags or patterns" do
      skill = build(:skill, tags: [], trigger_patterns: [])
      expect(skill.relevance_score_for("github pr")).to eq(0.0)
    end
  end

  describe "#security_status" do
    it "returns 'unscanned' when no scan result" do
      skill = build(:skill, security_scan_result: {})
      expect(skill.security_status).to eq("unscanned")
    end

    it "returns the status from scan result" do
      skill = build(:skill, :scanned_clean)
      expect(skill.security_status).to eq("clean")
    end

    it "returns 'flagged' for flagged skills" do
      skill = build(:skill, :scanned_flagged)
      expect(skill.security_status).to eq("flagged")
    end
  end

  describe "#security_clean?" do
    it "returns true for clean skills" do
      skill = build(:skill, :scanned_clean)
      expect(skill.security_clean?).to be true
    end

    it "returns false for flagged skills" do
      skill = build(:skill, :scanned_flagged)
      expect(skill.security_clean?).to be false
    end
  end

  describe "#security_blocked?" do
    it "returns false for clean skills" do
      skill = build(:skill, :scanned_clean)
      expect(skill.security_blocked?).to be false
    end

    it "returns true for blocked skills" do
      skill = build(:skill, security_scan_result: { "status" => "blocked" })
      expect(skill.security_blocked?).to be true
    end
  end

  describe "#compute_checksum" do
    it "sets checksum on save when content changes" do
      skill = create(:skill, content: "original content")
      expect(skill.checksum).to eq(Digest::SHA256.hexdigest("original content"))
    end

    it "updates checksum when content changes" do
      skill = create(:skill, content: "original")
      skill.update!(content: "updated")
      expect(skill.checksum).to eq(Digest::SHA256.hexdigest("updated"))
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
