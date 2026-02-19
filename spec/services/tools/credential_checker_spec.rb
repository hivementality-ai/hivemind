# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::CredentialChecker do
  describe "flat list (single provider)" do
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
        VaultEntry.create!(namespace: "twilio", key: "auth_token", encrypted_value: "secret", agent_id: nil)

        expect(described_class.ready?(tool)).to be false
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

  describe "multi-provider format" do
    let(:multi_provider_tool) do
      create(:tool, required_credentials: [
        {
          "provider" => "twilio",
          "credentials" => [
            { "namespace" => "twilio", "key" => "account_sid", "description" => "Twilio Account SID" },
            { "namespace" => "twilio", "key" => "auth_token", "description" => "Twilio Auth Token" },
            { "namespace" => "twilio", "key" => "from_number", "description" => "Twilio Phone Number" }
          ]
        },
        {
          "provider" => "telnyx",
          "credentials" => [
            { "namespace" => "telnyx", "key" => "api_key", "description" => "Telnyx API Key" },
            { "namespace" => "telnyx", "key" => "connection_id", "description" => "Telnyx Connection ID" }
          ]
        }
      ])
    end

    describe ".ready?" do
      it "returns false when no providers are configured" do
        expect(described_class.ready?(multi_provider_tool)).to be false
      end

      it "returns true when first provider is fully configured" do
        VaultEntry.create!(namespace: "twilio", key: "account_sid", encrypted_value: "AC123", agent_id: nil)
        VaultEntry.create!(namespace: "twilio", key: "auth_token", encrypted_value: "tok", agent_id: nil)
        VaultEntry.create!(namespace: "twilio", key: "from_number", encrypted_value: "+1555", agent_id: nil)

        expect(described_class.ready?(multi_provider_tool)).to be true
      end

      it "returns true when second provider is fully configured" do
        VaultEntry.create!(namespace: "telnyx", key: "api_key", encrypted_value: "key", agent_id: nil)
        VaultEntry.create!(namespace: "telnyx", key: "connection_id", encrypted_value: "conn", agent_id: nil)

        expect(described_class.ready?(multi_provider_tool)).to be true
      end

      it "returns false when provider is only partially configured" do
        VaultEntry.create!(namespace: "twilio", key: "account_sid", encrypted_value: "AC123", agent_id: nil)
        # Missing auth_token and from_number

        expect(described_class.ready?(multi_provider_tool)).to be false
      end
    end

    describe ".available_providers" do
      it "returns empty when no providers configured" do
        expect(described_class.available_providers(multi_provider_tool)).to be_empty
      end

      it "returns only fully configured providers" do
        VaultEntry.create!(namespace: "telnyx", key: "api_key", encrypted_value: "key", agent_id: nil)
        VaultEntry.create!(namespace: "telnyx", key: "connection_id", encrypted_value: "conn", agent_id: nil)

        result = described_class.available_providers(multi_provider_tool)
        expect(result).to eq([ "telnyx" ])
        expect(result).not_to include("twilio")
      end

      it "returns both when both configured" do
        VaultEntry.create!(namespace: "twilio", key: "account_sid", encrypted_value: "AC", agent_id: nil)
        VaultEntry.create!(namespace: "twilio", key: "auth_token", encrypted_value: "tok", agent_id: nil)
        VaultEntry.create!(namespace: "twilio", key: "from_number", encrypted_value: "+1", agent_id: nil)
        VaultEntry.create!(namespace: "telnyx", key: "api_key", encrypted_value: "key", agent_id: nil)
        VaultEntry.create!(namespace: "telnyx", key: "connection_id", encrypted_value: "conn", agent_id: nil)

        result = described_class.available_providers(multi_provider_tool)
        expect(result).to contain_exactly("twilio", "telnyx")
      end
    end

    describe ".unavailable_providers" do
      it "returns providers with their missing credentials" do
        VaultEntry.create!(namespace: "twilio", key: "account_sid", encrypted_value: "AC", agent_id: nil)

        result = described_class.unavailable_providers(multi_provider_tool)
        twilio_result = result.find { |r| r["provider"] == "twilio" }
        telnyx_result = result.find { |r| r["provider"] == "telnyx" }

        expect(twilio_result["missing"].length).to eq(2) # auth_token + from_number
        expect(telnyx_result["missing"].length).to eq(2) # api_key + connection_id
      end
    end

    describe ".missing_summary" do
      it "shows status of each provider" do
        VaultEntry.create!(namespace: "twilio", key: "account_sid", encrypted_value: "AC", agent_id: nil)

        result = described_class.missing_summary(multi_provider_tool)

        expect(result).to include("Requires one of these providers")
        expect(result).to include("❌ twilio")
        expect(result).to include("❌ telnyx")
        expect(result).to include("at least one provider")
      end

      it "shows checkmark for configured providers" do
        VaultEntry.create!(namespace: "telnyx", key: "api_key", encrypted_value: "key", agent_id: nil)
        VaultEntry.create!(namespace: "telnyx", key: "connection_id", encrypted_value: "conn", agent_id: nil)

        # Tool is ready (telnyx configured), so missing_summary returns nil
        expect(described_class.missing_summary(multi_provider_tool)).to be_nil
      end
    end
  end
end
