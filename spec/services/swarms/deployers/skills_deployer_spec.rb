# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Deployers::SkillsDeployer do
  def build_document(skills: [])
    Swarms::SwarmDocument.new(
      swarm_version: "1.0",
      name:          "Test Swarm",
      skills:        skills
    )
  end

  # ---------------------------------------------------------------------------
  # Result contract
  # ---------------------------------------------------------------------------

  describe "result contract" do
    it "always returns a successful ServiceResponse" do
      result = described_class.call(document: build_document)
      expect(result).to be_success
    end

    it "returns an empty skills array when the document has no skills" do
      result = described_class.call(document: build_document(skills: []))
      expect(result.payload[:skills]).to eq([])
    end

    it "returns one DeployResult per skill in the document" do
      doc    = build_document(skills: [
        { "name" => "skill-a", "content" => "# A", "summary" => "A skill" },
        { "name" => "skill-b", "content" => "# B", "summary" => "B skill" }
      ])
      result = described_class.call(document: doc)
      expect(result.payload[:skills].size).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # No conflict — create
  # ---------------------------------------------------------------------------

  describe "when no platform skill exists with that name" do
    it "creates a new Skill record" do
      doc = build_document(skills: [{ "name" => "new-skill", "content" => "# New", "summary" => "New skill" }])
      expect { described_class.call(document: doc) }.to change(Skill, :count).by(1)
    end

    it "returns action :created" do
      doc    = build_document(skills: [{ "name" => "new-skill", "content" => "# New", "summary" => "Summary" }])
      result = described_class.call(document: doc)
      expect(result.payload[:skills].first.action).to eq(:created)
    end

    it "stores all provided attributes" do
      doc    = build_document(skills: [{
        "name"        => "my-skill",
        "summary"     => "Does things",
        "description" => "A full description",
        "content"     => "# My Skill\n\nDoes things.",
        "category"    => "coding"
      }])
      result = described_class.call(document: doc)
      skill  = result.payload[:skills].first.record

      expect(skill.name).to eq("my-skill")
      expect(skill.summary).to eq("Does things")
      expect(skill.description).to eq("A full description")
      expect(skill.content).to eq("# My Skill\n\nDoes things.")
      expect(skill.category).to eq("coding")
      expect(skill.source).to eq("swarm")
    end

    it "uses a placeholder when content is absent" do
      doc   = build_document(skills: [{ "name" => "bare-skill", "summary" => "Summary" }])
      skill = described_class.call(document: doc).payload[:skills].first.record
      expect(skill.content).to eq("# Imported from swarm")
    end

    it "sets enabled true by default" do
      doc   = build_document(skills: [{ "name" => "enabled-skill", "summary" => "S", "content" => "C" }])
      skill = described_class.call(document: doc).payload[:skills].first.record
      expect(skill.enabled).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Strategy: :skip
  # ---------------------------------------------------------------------------

  describe "strategy :skip" do
    it "returns the existing skill unchanged" do
      existing = create(:skill, name: "dupe-skill", summary: "Old summary", content: "old")
      doc      = build_document(skills: [{ "name" => "dupe-skill", "summary" => "New summary", "content" => "new" }])
      result   = described_class.call(document: doc, resolutions: { "dupe-skill" => :skip })

      dr = result.payload[:skills].first
      expect(dr.action).to eq(:skipped)
      expect(dr.record).to eq(existing)
      expect(existing.reload.summary).to eq("Old summary")
    end

    it "does not create a new skill" do
      create(:skill, name: "dupe-skill", content: "x", summary: "S")
      doc = build_document(skills: [{ "name" => "dupe-skill", "content" => "y", "summary" => "S" }])
      expect { described_class.call(document: doc, resolutions: { "dupe-skill" => :skip }) }.not_to change(Skill, :count)
    end
  end

  # ---------------------------------------------------------------------------
  # Strategy: :overwrite
  # ---------------------------------------------------------------------------

  describe "strategy :overwrite" do
    it "updates the existing skill's attributes" do
      existing = create(:skill, name: "my-skill", summary: "Old", content: "old content")
      doc      = build_document(skills: [{
        "name"    => "my-skill",
        "summary" => "Updated summary",
        "content" => "updated content"
      }])
      result = described_class.call(document: doc, resolutions: { "my-skill" => :overwrite })

      dr = result.payload[:skills].first
      expect(dr.action).to eq(:updated)
      expect(dr.record).to eq(existing)
      expect(existing.reload.summary).to eq("Updated summary")
      expect(existing.reload.content).to eq("updated content")
    end
  end

  # ---------------------------------------------------------------------------
  # Strategy: :rename
  # ---------------------------------------------------------------------------

  describe "strategy :rename" do
    it "creates a new skill with a suffixed name" do
      create(:skill, name: "alpha-skill", content: "x", summary: "S")
      doc    = build_document(skills: [{ "name" => "alpha-skill", "content" => "y", "summary" => "S" }])
      result = described_class.call(document: doc, resolutions: { "alpha-skill" => :rename })

      dr = result.payload[:skills].first
      expect(dr.action).to eq(:renamed)
      expect(dr.record.name).to eq("alpha-skill-2")
    end

    it "increments suffix when -2 already exists" do
      create(:skill, name: "alpha-skill", content: "x", summary: "S")
      create(:skill, name: "alpha-skill-2", content: "x", summary: "S")
      doc    = build_document(skills: [{ "name" => "alpha-skill", "content" => "y", "summary" => "S" }])
      result = described_class.call(document: doc, resolutions: { "alpha-skill" => :rename })

      expect(result.payload[:skills].first.record.name).to eq("alpha-skill-3")
    end
  end

  # ---------------------------------------------------------------------------
  # Multiple skills in one document
  # ---------------------------------------------------------------------------

  describe "with multiple skills" do
    it "handles mixed strategies independently" do
      create(:skill, name: "existing-skill", content: "x", summary: "S")
      doc = build_document(skills: [
        { "name" => "existing-skill", "content" => "y", "summary" => "S" },
        { "name" => "new-skill",      "content" => "z", "summary" => "S" }
      ])
      result = described_class.call(document: doc, resolutions: { "existing-skill" => :skip })
      actions = result.payload[:skills].map(&:action)

      expect(actions).to eq(%i[skipped created])
    end

    it "creates all new skills" do
      doc = build_document(skills: [
        { "name" => "skill-1", "content" => "a", "summary" => "S" },
        { "name" => "skill-2", "content" => "b", "summary" => "S" },
        { "name" => "skill-3", "content" => "c", "summary" => "S" }
      ])
      expect { described_class.call(document: doc) }.to change(Skill, :count).by(3)
    end
  end
end
