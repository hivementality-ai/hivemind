# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::CredentialChecker do
  describe ".ready?" do
    it "returns true when tool has no required credentials" do
      tool = create(:tool, required_credentials: [])
      expect(described_class.ready?(tool)).to be true
    end

    it "returns true when tool has nil required credentials" do
      tool = create(:tool, required_credentials: nil)
      expect(described_class.ready?(tool)).to be true
    end

    it "returns true when all credentials exist" do
      tool = create(:tool, required_credentials: [
        { "namespace" => "twilio", "key" => "auth_token", "description" => "Twilio Auth Token" }
      ])

      VaultEntry.create!(namespace: "twilio", key: "auth_token", encrypted_value: "secret", agent_id: nil)

      expect(described_class.ready?(tool)).to be true
    end

    it "returns false when credentials are missing" do
      tool = create(:tool, required_credentials: [
        { "namespace" => "twilio", "key" => "auth_token", "description" => "Twilio Auth Token" },
        { "namespace" => "twilio", "key" => "account_sid", "description" => "Twilio Account SID" }
      ])

      # Only one of two exists
      VaultEntry.create!(namespace: "twilio", key: "auth_token", encrypted_value: "secret", agent_id: nil)

      expect(described_class.ready?(tool)).to be false
    end
  end

  describe ".missing" do
    it "returns empty array when all present" do
      tool = create(:tool, required_credentials: [
        { "namespace" => "test", "key" => "key1", "description" => "Key 1" }
      ])
      VaultEntry.create!(namespace: "test", key: "key1", encrypted_value: "val", agent_id: nil)

      expect(described_class.missing(tool)).to be_empty
    end

    it "returns missing credentials" do
      tool = create(:tool, required_credentials: [
        { "namespace" => "twilio", "key" => "auth_token", "description" => "Twilio Auth Token" },
        { "namespace" => "twilio", "key" => "account_sid", "description" => "Twilio Account SID" }
      ])

      missing = described_class.missing(tool)
      expect(missing.length).to eq(2)
      expect(missing.map { |c| c["key"] }).to contain_exactly("auth_token", "account_sid")
    end
  end

  describe ".missing_summary" do
    it "returns nil when all credentials present" do
      tool = create(:tool, required_credentials: [])
      expect(described_class.missing_summary(tool)).to be_nil
    end

    it "returns singular message for one missing credential" do
      tool = create(:tool, required_credentials: [
        { "namespace" => "twilio", "key" => "auth_token", "description" => "Twilio Auth Token" }
      ])

      result = described_class.missing_summary(tool)
      expect(result).to include("Missing credential")
      expect(result).to include("Twilio Auth Token")
    end

    it "returns plural message for multiple missing credentials" do
      tool = create(:tool, required_credentials: [
        { "namespace" => "twilio", "key" => "auth_token", "description" => "Twilio Auth Token" },
        { "namespace" => "twilio", "key" => "account_sid", "description" => "Twilio Account SID" }
      ])

      result = described_class.missing_summary(tool)
      expect(result).to include("Missing credentials")
      expect(result).to include("Twilio Auth Token")
      expect(result).to include("Twilio Account SID")
    end
  end
end
