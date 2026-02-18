# frozen_string_literal: true

require "rails_helper"

RSpec.describe Vault::WriteConfirmation do
  let(:agent) { create(:agent, name: "TestAgent") }

  describe ".request_write" do
    it "returns pending confirmation with redacted value" do
      result = described_class.request_write(
        agent: agent,
        namespace: "twilio",
        key: "auth_token",
        value: "abc123def456ghi789",
        purpose: "Twilio auth for voice calls"
      )

      expect(result[:status]).to eq("pending_confirmation")
      expect(result[:confirmation_id]).to be_present
      expect(result[:explanation][:redacted_value]).to end_with("i789")
      expect(result[:explanation][:redacted_value]).not_to include("abc123")
      expect(result[:explanation][:purpose]).to eq("Twilio auth for voice calls")
      expect(result[:explanation][:scope]).to include("Global")
      expect(result[:expires_in_minutes]).to eq(15)
    end

    it "identifies known key formats" do
      result = described_class.request_write(
        agent: agent,
        namespace: "providers",
        key: "openai_api_key",
        value: "sk-proj-abc123xyz789"
      )

      expect(result[:explanation][:identified_as]).to include("OpenAI")
    end

    it "includes requesting agent name" do
      result = described_class.request_write(
        agent: agent,
        namespace: "test",
        key: "key",
        value: "value12345678"
      )

      expect(result[:explanation][:requested_by]).to eq("TestAgent")
    end
  end

  describe ".confirm_write" do
    before do
      # Mock Redis for pending confirmation
      allow_any_instance_of(described_class)
        .to receive(:retrieve_pending)
        .and_return(
          "agent_id" => agent.id,
          "agent_name" => agent.name,
          "namespace" => "twilio",
          "key" => "auth_token",
          "value" => "secretvalue1234",
          "purpose" => "Twilio auth",
          "tool_binding" => "voice_call"
        )
      allow_any_instance_of(described_class).to receive(:delete_pending)
    end

    it "creates a global vault entry" do
      result = described_class.confirm_write(
        confirmation_id: "valid_token",
        agent: agent
      )

      expect(result[:status]).to eq("written")
      expect(result[:key]).to eq("twilio.auth_token")

      entry = VaultEntry.find_by(namespace: "twilio", key: "auth_token", agent_id: nil)
      expect(entry).to be_present
      expect(entry.tool_binding).to eq("voice_call")
    end

    it "returns redacted value in confirmation" do
      result = described_class.confirm_write(
        confirmation_id: "valid_token",
        agent: agent
      )

      expect(result[:redacted_value]).to end_with("1234")
      expect(result[:redacted_value]).not_to include("secretvalue")
    end

    it "creates an audit log" do
      expect {
        described_class.confirm_write(confirmation_id: "valid_token", agent: agent)
      }.to change(AuditLog, :count).by(1)

      log = AuditLog.last
      expect(log.action).to eq("vault_write")
      expect(log.actor_type).to eq("Agent")
      expect(log.resource).to include("VaultEntry")
      expect(log.metadata["key"]).to eq("auth_token")
      expect(log.metadata["redacted_value"]).to include("•")
    end

    it "returns error when confirmation expired" do
      allow_any_instance_of(described_class).to receive(:retrieve_pending).and_return(nil)

      result = described_class.confirm_write(
        confirmation_id: "expired_token",
        agent: agent
      )

      expect(result[:status]).to eq("error")
      expect(result[:message]).to include("expired or invalid")
    end

    it "stores purpose in metadata" do
      described_class.confirm_write(confirmation_id: "valid_token", agent: agent)

      entry = VaultEntry.find_by(namespace: "twilio", key: "auth_token", agent_id: nil)
      expect(entry.metadata["purpose"]).to eq("Twilio auth")
      expect(entry.metadata["written_by_agent"]).to eq("TestAgent")
    end
  end
end
