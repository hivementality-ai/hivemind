# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::SkillCreator, type: :service do
  let(:team) { create(:team) }
  let(:agent) { create(:agent, team: team) }
  let(:teammate) { create(:agent, team: team) }

  let(:valid_params) do
    {
      agent: agent,
      name: "test_skill",
      summary: "A test skill for testing",
      content: "# Test Skill\n\nDo the thing.",
      category: "utilities"
    }
  end

  before do
    # Ensure teammate exists before creation calls
    teammate

    # Stub security scanner to return clean by default
    allow(SkillSecurityScanner).to receive(:call).and_return(
      ServiceResponse.success(data: {
        status: "clean",
        risk_level: "low",
        blocked: false,
        findings: [],
        blocklist_reasons: [],
        checksum: "abc123",
        source: "agent",
        scanned_at: Time.current.iso8601,
        patterns_checked: 10
      })
    )
  end

  describe ".call" do
    it "creates and auto-approves a clean skill" do
      result = described_class.call(**valid_params)

      expect(result).to be_success
      expect(result.data[:status]).to eq("active")

      skill = Skill.find_by(name: "test_skill")
      expect(skill).to be_present
      expect(skill.enabled).to be true
      expect(skill.approved_at).to be_present
      expect(skill.source).to eq("agent")
      expect(skill.metadata["created_by_agent_id"]).to eq(agent.id)
    end

    it "assigns the skill to the creating agent" do
      described_class.call(**valid_params)

      expect(agent.skills.pluck(:name)).to include("test_skill")
    end

    it "shares with team when requested" do
      described_class.call(**valid_params, share_with_team: true)

      expect(teammate.skills.pluck(:name)).to include("test_skill")
    end

    it "does not share with team by default" do
      described_class.call(**valid_params)

      expect(teammate.skills.pluck(:name)).not_to include("test_skill")
    end

    it "queues flagged skills for approval" do
      allow(SkillSecurityScanner).to receive(:call).and_return(
        ServiceResponse.success(data: {
          status: "warning",
          risk_level: "medium",
          blocked: false,
          findings: [{ severity: "medium", pattern: "test" }],
          blocklist_reasons: [],
          checksum: "abc123",
          source: "agent",
          scanned_at: Time.current.iso8601,
          patterns_checked: 10
        })
      )

      result = described_class.call(**valid_params)

      expect(result).to be_success
      expect(result.data[:status]).to eq("pending_review")

      skill = Skill.find_by(name: "test_skill")
      expect(skill.enabled).to be false
    end

    it "blocks skills that fail security scan" do
      allow(SkillSecurityScanner).to receive(:call).and_return(
        ServiceResponse.success(data: {
          status: "blocked",
          blocked: true,
          blocklist_reasons: ["malicious pattern detected"]
        })
      )

      result = described_class.call(**valid_params)
      expect(result).not_to be_success
      expect(result.error).to include("blocked")
    end

    it "fails when name is blank" do
      result = described_class.call(**valid_params.merge(name: ""))
      expect(result).not_to be_success
      expect(result.error).to eq("Name is required")
    end

    it "fails when skill already exists" do
      create(:skill, name: "test_skill")

      result = described_class.call(**valid_params)
      expect(result).not_to be_success
      expect(result.error).to include("already exists")
    end

    it "defaults category to utilities" do
      described_class.call(**valid_params.merge(category: nil))

      skill = Skill.find_by(name: "test_skill")
      expect(skill.category).to eq("utilities")
    end
  end
end
