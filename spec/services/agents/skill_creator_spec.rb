# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::SkillCreator, type: :service do
  let(:team)     { create(:team) }
  let(:agent)    { create(:agent, team: team) }
  let(:teammate) { create(:agent, team: team) }

  # Content long enough to pass ProposalValidator (>= 200 chars, has ## heading)
  let(:valid_content) do
    <<~MD
      ## Overview

      This skill teaches the agent how to perform the test operation reliably.
      Follow each step in order and verify the output before proceeding to the next.

      ## Usage

      Call this skill when you need to run integration tests against the remote API.
    MD
  end

  let(:valid_params) do
    {
      agent: agent,
      name: "test_skill",
      summary: "A test skill for testing purposes",
      content: valid_content,
      category: "utilities"
    }
  end

  let(:clean_scan) do
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
  end

  before do
    teammate # ensure teammate exists
    allow(SkillSecurityScanner).to receive(:call).and_return(clean_scan)
  end

  describe ".call" do
    context "with valid params and clean scan" do
      it "creates the skill as a pending proposal" do
        result = described_class.call(**valid_params)

        expect(result).to be_success
        expect(result.data[:status]).to eq("pending_review")

        skill = Skill.find_by(name: "test_skill")
        expect(skill).to be_present
        expect(skill.enabled).to be false
        expect(skill.proposal_status).to eq("pending")
        expect(skill.proposed_by_agent_id).to eq(agent.id)
        expect(skill.proposed_at).to be_present
        expect(skill.source).to eq("agent")
      end

      it "creates an ApprovalRequest for admin review" do
        expect { described_class.call(**valid_params) }
          .to change(ApprovalRequest, :count).by(1)

        request = ApprovalRequest.last
        expect(request.action).to eq("create_skill")
        expect(request.params["skill_name"]).to eq("test_skill")
      end

      it "does not assign the skill to the agent yet (pending admin approval)" do
        described_class.call(**valid_params)
        expect(agent.skills.pluck(:name)).not_to include("test_skill")
      end

      it "does not auto-enable even when scan is clean" do
        described_class.call(**valid_params)
        skill = Skill.find_by(name: "test_skill")
        expect(skill.enabled).to be false
      end
    end

    context "quality guardrails" do
      it "rejects content that is too short" do
        result = described_class.call(**valid_params.merge(content: "## Hi\n\nShort."))
        expect(result).not_to be_success
        expect(result.error).to include("200 characters")
      end

      it "rejects content with no section headings" do
        no_headings = "a" * 250  # long enough but no ## headings
        result = described_class.call(**valid_params.merge(content: no_headings))
        expect(result).not_to be_success
        expect(result.error).to include("section heading")
      end

      it "rejects names with invalid characters" do
        result = described_class.call(**valid_params.merge(name: "My Skill!!"))
        expect(result).not_to be_success
        expect(result.error).to include("lowercase")
      end

      it "rejects content containing apparent credentials" do
        secret_content = valid_content + "\napi_key: sk-abc123def456ghi789jkl012mno345pqr678"
        result = described_class.call(**valid_params.merge(content: secret_content))
        expect(result).not_to be_success
        expect(result.error).to include("sensitive data")
      end

      it "rejects a blank summary" do
        result = described_class.call(**valid_params.merge(summary: ""))
        expect(result).not_to be_success
        expect(result.error).to include("Summary is required")
      end
    end

    context "security scan" do
      it "rejects blocked skills immediately" do
        allow(SkillSecurityScanner).to receive(:call).and_return(
          ServiceResponse.success(data: {
            status: "blocked",
            blocked: true,
            blocklist_reasons: [ "malicious pattern detected" ]
          })
        )

        result = described_class.call(**valid_params)
        expect(result).not_to be_success
        expect(result.error).to include("blocked by security scan")
        expect(Skill.exists?(name: "test_skill")).to be false
      end

      it "stores the scan result on the skill even when flagged (not blocked)" do
        allow(SkillSecurityScanner).to receive(:call).and_return(
          ServiceResponse.success(data: {
            status: "warning",
            risk_level: "medium",
            blocked: false,
            findings: [ { severity: "medium", pattern: "eval" } ],
            blocklist_reasons: [],
            checksum: "abc123",
            source: "agent",
            scanned_at: Time.current.iso8601,
            patterns_checked: 10
          })
        )

        result = described_class.call(**valid_params)
        expect(result).to be_success

        skill = Skill.find_by(name: "test_skill")
        expect(skill.security_scan_result["status"]).to eq("warning")
        expect(skill.proposal_status).to eq("pending")
      end
    end

    context "duplicate detection" do
      it "fails when a skill with the same name already exists" do
        create(:skill, name: "test_skill")

        result = described_class.call(**valid_params)
        expect(result).not_to be_success
        expect(result.error).to include("already exists")
      end
    end

    context "category resolution" do
      it "defaults to utilities when category is nil" do
        described_class.call(**valid_params.merge(category: nil))
        expect(Skill.find_by(name: "test_skill").category).to eq("utilities")
      end

      it "defaults to utilities when category is unknown" do
        described_class.call(**valid_params.merge(category: "nonsense"))
        expect(Skill.find_by(name: "test_skill").category).to eq("utilities")
      end

      it "uses the provided category when valid" do
        described_class.call(**valid_params.merge(category: "coding"))
        expect(Skill.find_by(name: "test_skill").category).to eq("coding")
      end
    end
  end
end
