# frozen_string_literal: true

require "rails_helper"

RSpec.describe Skill, "agentskills.io compatibility" do
  describe "#to_skill_md / .from_skill_md round-trip" do
    it "preserves name, description, category, tags, license, version, and source_url" do
      skill = Skill.new(
        name: "deploy-helper",
        description: "Helps deploy: staging and prod",
        summary: "deploy helper",
        content: "Run the deploy steps.",
        category: "automation",
        tags: %w[deploy ops],
        source_url: "https://hub.example/skills/deploy-helper",
        metadata: { "license" => "MIT", "version" => "1.2.0" }
      )

      md = skill.to_skill_md
      expect(md).to include("name: deploy-helper")
      expect(md).to include("license: MIT")
      # description has a colon — must survive the YAML round-trip
      expect(md).to include("staging and prod")

      parsed = described_class.from_skill_md(md)
      expect(parsed.description).to eq("Helps deploy: staging and prod")
      expect(parsed.name).to eq("deploy-helper")
      expect(parsed.category).to eq("automation")
      expect(parsed.tags).to eq(%w[deploy ops])
      expect(parsed.source_url).to eq("https://hub.example/skills/deploy-helper")
      expect(parsed.metadata["license"]).to eq("MIT")
      expect(parsed.metadata["version"]).to eq("1.2.0")
    end

    it "parses a nested agentskills.io metadata block" do
      md = <<~MD
        ---
        name: research-assistant
        description: Finds and summarizes sources
        metadata:
          category: productivity
          tags: [research, web]
          license: Apache-2.0
        ---
        Do the research.
      MD

      parsed = described_class.from_skill_md(md)
      expect(parsed.category).to eq("productivity")
      expect(parsed.tags).to eq(%w[research web])
      expect(parsed.metadata["license"]).to eq("Apache-2.0")
    end

    it "still reads legacy flat OpenClaw frontmatter" do
      md = "---\nname: legacy\ndescription: old style\ncategory: coding\n---\nbody"
      parsed = described_class.from_skill_md(md)
      expect(parsed.name).to eq("legacy")
      expect(parsed.category).to eq("coding")
    end
  end
end
