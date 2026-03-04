# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClawHub::SkillInstaller do
  describe ".call" do
    subject(:result) { described_class.call(slug: slug, user: user) }

    let(:user) { create(:user, :owner) }
    let(:slug) { "test-skill" }
    let(:client) { instance_double(ClawHub::Client) }

    let(:skill_detail) do
      {
        "skill" => { "slug" => slug, "displayName" => "Test Skill", "stats" => { "downloads" => 50 } },
        "latestVersion" => { "version" => "1.0.0", "files" => ["test-skill.SKILL.md"] }
      }
    end

    let(:skill_md_content) do
      "---\nname: Test Skill\ndescription: A test skill\nsummary: A test\n---\nDo testing things."
    end

    before do
      allow(ClawHub::Client).to receive(:new).and_return(client)
      allow(client).to receive(:get_skill).with(slug: slug).and_return(skill_detail)
      allow(client).to receive(:get_skill_file).and_return(skill_md_content)
    end

    context "when security scan is clean" do
      before do
        allow(SkillSecurityScanner).to receive(:call).and_return(
          ServiceResponse.success(data: {
            status: "clean",
            risk_level: "low",
            blocked: false,
            findings: [],
            blocklist_reasons: [],
            checksum: "abc123",
            source: "clawhub",
            scanned_at: Time.current.iso8601,
            patterns_checked: 10
          })
        )
      end

      it "creates a new skill" do
        expect { result }.to change(Skill, :count).by(1)
        expect(result).to be_success
        expect(result.data[:status]).to eq("installed")
        expect(result.data[:skill].source).to eq("clawhub")
        expect(result.data[:skill].source_url).to eq("https://clawhub.ai/skills/test-skill")
      end

      it "sets skill attributes from the SKILL.md" do
        result
        skill = result.data[:skill]
        expect(skill.name).to eq("Test Skill")
        expect(skill.content).to eq("Do testing things.")
      end

      context "when skill already installed from clawhub" do
        let!(:existing) do
          create(:skill, name: "Test Skill", source: "clawhub", source_url: "https://clawhub.ai/skills/test-skill")
        end

        it "updates the existing skill" do
          expect { result }.not_to change(Skill, :count)
          expect(result.data[:skill].id).to eq(existing.id)
          expect(result.data[:status]).to eq("installed")
        end
      end
    end

    context "when security scan returns flagged" do
      before do
        allow(SkillSecurityScanner).to receive(:call).and_return(
          ServiceResponse.success(data: {
            status: "flagged",
            risk_level: "critical",
            blocked: false,
            findings: [{ severity: "critical", description: "Suspicious pattern" }],
            blocklist_reasons: [],
            checksum: "abc123",
            source: "clawhub",
            scanned_at: Time.current.iso8601,
            patterns_checked: 10
          })
        )
      end

      it "returns pending_review status without creating skill" do
        expect { result }.not_to change(Skill, :count)
        expect(result).to be_success
        expect(result.data[:status]).to eq("pending_review")
        expect(result.data[:pending_attributes][:name]).to eq("Test Skill")
        expect(result.data[:pending_attributes][:source]).to eq("clawhub")
      end
    end

    context "when security scan returns blocked" do
      before do
        allow(SkillSecurityScanner).to receive(:call).and_return(
          ServiceResponse.success(data: {
            status: "blocked",
            risk_level: "critical",
            blocked: true,
            findings: [],
            blocklist_reasons: ["Known malicious"],
            checksum: "abc123",
            source: "clawhub",
            scanned_at: Time.current.iso8601,
            patterns_checked: 10
          })
        )
      end

      it "returns blocked status without creating skill" do
        expect { result }.not_to change(Skill, :count)
        expect(result).to be_success
        expect(result.data[:status]).to eq("blocked")
      end
    end

    context "when security scan fails" do
      before do
        allow(SkillSecurityScanner).to receive(:call).and_return(
          ServiceResponse.failure(error: "Scan error")
        )
      end

      it "returns failure" do
        expect(result).not_to be_success
        expect(result.error).to include("Security scan failed")
      end
    end

    context "when ClawHub API fails" do
      before do
        allow(client).to receive(:get_skill).and_raise(ClawHub::ApiError.new("Not found", status: 404))
      end

      it "returns failure" do
        expect(result).not_to be_success
        expect(result.error).to include("ClawHub API error")
      end
    end

    context "when skill_md has no name" do
      let(:skill_md_content) { "---\ndescription: No name skill\nsummary: A test\n---\nContent" }

      before do
        allow(SkillSecurityScanner).to receive(:call).and_return(
          ServiceResponse.success(data: { status: "clean", risk_level: "low", blocked: false, findings: [], blocklist_reasons: [], checksum: "abc", source: "clawhub", scanned_at: Time.current.iso8601, patterns_checked: 10 })
        )
      end

      it "falls back to displayName from API" do
        result
        expect(result.data[:skill].name).to eq("Test Skill")
      end
    end
  end
end
