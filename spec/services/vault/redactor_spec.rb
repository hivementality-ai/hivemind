# frozen_string_literal: true

require "rails_helper"

RSpec.describe Vault::Redactor do
  describe ".redact" do
    it "redacts OpenAI keys with prefix" do
      result = described_class.redact("sk-proj-abc123xyz789def456")
      expect(result).to start_with("sk-")
      expect(result).to end_with("f456")
      expect(result).to include("•")
      expect(result).not_to include("abc123")
    end

    it "redacts Anthropic keys with prefix" do
      result = described_class.redact("sk-ant-api03-longkeyhere1234")
      expect(result).to start_with("sk-ant-")
      expect(result).to end_with("1234")
    end

    it "redacts Twilio Account SID with prefix" do
      result = described_class.redact("AC1234567890abcdef1234")
      expect(result).to start_with("AC")
      expect(result).to end_with("1234")
      expect(result).not_to include("567890")
    end

    it "redacts Google API keys with prefix" do
      result = described_class.redact("AIzaSyB-abc123xyz789")
      expect(result).to start_with("AIza")
      expect(result).to end_with("z789")
    end

    it "redacts GitHub PATs with prefix" do
      result = described_class.redact("ghp_abc123xyz789def456ghi")
      expect(result).to start_with("ghp_")
      expect(result).to end_with("6ghi")
    end

    it "redacts Slack tokens with prefix" do
      result = described_class.redact("xoxb-123456-789012-abcdef")
      expect(result).to start_with("xoxb-")
      expect(result).to end_with("cdef")
    end

    it "redacts phone numbers with prefix" do
      result = described_class.redact("+15551234567")
      expect(result).to start_with("+1")
      expect(result).to end_with("4567")
    end

    it "redacts unknown format keys (no prefix, last 4 visible)" do
      result = described_class.redact("mysecretapikey12345")
      expect(result).to end_with("2345")
      expect(result).not_to include("mysecret")
    end

    it "handles short keys" do
      result = described_class.redact("short")
      expect(result).to end_with("ort")
      expect(result).to include("•")
    end

    it "handles very short keys (< 4 chars)" do
      result = described_class.redact("abc")
      expect(result).to eq("•••")
    end

    it "handles nil" do
      expect(described_class.redact(nil)).to eq("••••")
    end

    it "handles empty string" do
      expect(described_class.redact("")).to eq("••••")
    end

    it "never exposes more than prefix + last 4" do
      key = "sk-proj-thisisaverylongsecretkeyvalue1234"
      result = described_class.redact(key)
      # Remove known prefix (sk-proj-) and suffix (1234)
      middle = result.gsub(/\Ask-proj-/, "").gsub(/1234\z/, "")
      expect(middle).to match(/\A•+\z/)
    end
  end

  describe ".identify" do
    it "identifies OpenAI keys" do
      expect(described_class.identify("sk-proj-abc123")).to include("OpenAI")
    end

    it "identifies Twilio SIDs" do
      expect(described_class.identify("AC1234567890")).to include("Twilio")
    end

    it "identifies GitHub PATs" do
      expect(described_class.identify("ghp_abc123xyz")).to include("GitHub")
    end

    it "identifies phone numbers" do
      expect(described_class.identify("+15551234567")).to include("Phone")
    end

    it "returns nil for unknown formats" do
      expect(described_class.identify("randomvalue123")).to be_nil
    end

    it "returns nil for nil" do
      expect(described_class.identify(nil)).to be_nil
    end
  end
end
