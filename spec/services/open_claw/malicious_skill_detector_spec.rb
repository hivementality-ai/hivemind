# frozen_string_literal: true

require "rails_helper"

RSpec.describe OpenClaw::MaliciousSkillDetector do
  describe ".call" do
    subject(:result) { described_class.call(content: content, name: name) }

    let(:content) { "# Safe Skill\n\nHelp users write code." }
    let(:name) { "my-safe-skill" }

    context "with clean content and name" do
      it "returns success with not blocked" do
        expect(result).to be_success
        expect(result.data[:blocked]).to be false
        expect(result.data[:reasons]).to be_empty
      end

      it "includes a checksum" do
        expect(result.data[:checksum]).to eq(Digest::SHA256.hexdigest(content))
      end

      it "includes checked_at timestamp" do
        expect(result.data[:checked_at]).to be_present
      end
    end

    context "with blocklisted checksum" do
      let(:malicious_checksum) { Digest::SHA256.hexdigest(content) }

      before do
        stub_const("OpenClaw::MaliciousSkillDetector::BLOCKLIST", Set.new([malicious_checksum]))
      end

      it "returns blocked" do
        expect(result.data[:blocked]).to be true
        expect(result.data[:reasons]).to include("Content checksum matches known malicious skill")
      end
    end

    context "with blocklisted name" do
      let(:name) { "evil-backdoor" }

      before do
        stub_const("OpenClaw::MaliciousSkillDetector::NAME_BLOCKLIST", Set.new(["evil-backdoor"]))
      end

      it "returns blocked" do
        expect(result.data[:blocked]).to be true
        expect(result.data[:reasons]).to include("Skill name matches known malicious skill")
      end
    end

    context "with nil name" do
      let(:name) { nil }

      it "returns success without checking name blocklist" do
        expect(result).to be_success
        expect(result.data[:blocked]).to be false
      end
    end
  end
end
