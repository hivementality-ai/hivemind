# frozen_string_literal: true

require "rails_helper"

RSpec.describe OpenClaw::SkillParser do
  let(:agent) { create(:agent) }

  after { cleanup_openclaw_workspace(@workspace_path) if @workspace_path }

  describe ".call" do
    context "with clean skills" do
      before do
        @workspace_path = create_openclaw_workspace(
          skills: {
            "greet.SKILL.md" => default_skill_md(name: "greet", description: "Greets the user", content: "Say hello warmly.")
          }
        )
      end

      it "imports the skill" do
        result = described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(result).to be_success
        expect(result.data[:imported].size).to eq(1)
        expect(result.data[:imported].first[:name]).to eq("greet")
        expect(result.data[:skipped]).to be_empty
      end

      it "creates the Skill record" do
        described_class.call(workspace_path: @workspace_path, agent: agent)

        skill = Skill.find_by(name: "greet")
        expect(skill).to be_present
        expect(skill.source).to eq("openclaw")
        expect(skill.security_scan_result).to be_present
      end

      it "creates the AgentSkill join" do
        described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(AgentSkill.exists?(agent: agent, skill: Skill.find_by(name: "greet"))).to be true
      end
    end

    context "with malicious skills" do
      before do
        @workspace_path = create_openclaw_workspace(
          skills: {
            "evil.SKILL.md" => malicious_skill_md(name: "evil_skill")
          }
        )
      end

      it "skips blocked/flagged skills" do
        result = described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(result).to be_success
        expect(result.data[:imported]).to be_empty
        expect(result.data[:skipped].size).to eq(1)
        expect(result.data[:skipped].first[:reason]).to match(/Security scan/)
      end

      it "does not create a Skill record" do
        described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(Skill.find_by(name: "evil_skill")).to be_nil
      end
    end

    context "with duplicate skill names (idempotent re-run)" do
      before do
        @workspace_path = create_openclaw_workspace(
          skills: {
            "greet.SKILL.md" => default_skill_md(name: "greet", description: "Greets the user", content: "Say hello warmly.")
          }
        )
      end

      it "updates existing skill instead of creating duplicate" do
        # First run
        described_class.call(workspace_path: @workspace_path, agent: agent)
        # Second run
        result = described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(result).to be_success
        expect(Skill.where(name: "greet").count).to eq(1)
      end
    end

    context "without skills directory" do
      before do
        @workspace_path = create_openclaw_workspace(skills: {})
      end

      it "returns empty results" do
        result = described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(result).to be_success
        expect(result.data[:imported]).to be_empty
        expect(result.data[:skipped]).to be_empty
      end
    end

    context "with mixed clean and flagged skills" do
      before do
        @workspace_path = create_openclaw_workspace(
          skills: {
            "good.SKILL.md" => default_skill_md(name: "good_skill", description: "Helpful skill", content: "Help the user."),
            "bad.SKILL.md" => malicious_skill_md(name: "bad_skill")
          }
        )
      end

      it "imports clean and skips flagged" do
        result = described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(result).to be_success
        imported_names = result.data[:imported].map { |s| s[:name] }
        skipped_names = result.data[:skipped].map { |s| s[:name] }

        expect(imported_names).to include("good_skill")
        expect(skipped_names).to include("bad_skill")
      end
    end
  end
end
