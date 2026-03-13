# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleWorkspace::CredentialBridge, type: :service do
  let(:namespace) { "google_workspace" }

  describe ".configured?" do
    it "returns false when no tokens exist" do
      expect(described_class.configured?).to be false
    end

    it "returns true when access and refresh tokens exist" do
      create(:vault_entry, namespace: namespace, key: "access_token", value: "ya29.test")
      create(:vault_entry, namespace: namespace, key: "refresh_token", value: "1//test")

      expect(described_class.configured?).to be true
    end
  end

  describe ".store_tokens" do
    it "stores all token data in vault" do
      described_class.store_tokens(
        access_token: "ya29.test",
        refresh_token: "1//refresh",
        expires_in: 3600,
        scope: "drive calendar",
        email: "user@example.com"
      )

      expect(VaultEntry.find_by(namespace: namespace, key: "access_token").value).to eq("ya29.test")
      expect(VaultEntry.find_by(namespace: namespace, key: "refresh_token").value).to eq("1//refresh")
      expect(VaultEntry.find_by(namespace: namespace, key: "scopes").value).to eq("drive calendar")
      expect(VaultEntry.find_by(namespace: namespace, key: "email").value).to eq("user@example.com")
      expect(VaultEntry.find_by(namespace: namespace, key: "expires_at").value).to be_present
    end
  end

  describe ".disconnect!" do
    before do
      %w[access_token refresh_token expires_at scopes email].each do |key|
        create(:vault_entry, namespace: namespace, key: key, value: "test")
      end
    end

    it "removes all token entries" do
      described_class.disconnect!

      %w[access_token refresh_token expires_at scopes email].each do |key|
        expect(VaultEntry.find_by(namespace: namespace, key: key)).to be_nil
      end
    end
  end

  describe ".connected_email" do
    it "returns nil when not connected" do
      expect(described_class.connected_email).to be_nil
    end

    it "returns the stored email" do
      create(:vault_entry, namespace: namespace, key: "email", value: "user@example.com")
      expect(described_class.connected_email).to eq("user@example.com")
    end
  end
end
