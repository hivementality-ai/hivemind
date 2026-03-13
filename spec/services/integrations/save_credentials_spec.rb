# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::SaveCredentials, type: :service do
  describe ".call" do
    it "saves credentials to vault" do
      result = described_class.call(
        namespace: "github",
        fields: { token: "ghp_test123" },
        required: %i[token]
      )

      expect(result).to be_success
      expect(VaultEntry.find_by(namespace: "github", key: "token")).to be_present
    end

    it "returns failure when required fields are missing" do
      result = described_class.call(
        namespace: "jira",
        fields: { base_url: "https://test.atlassian.net", email: "", api_token: "" },
        required: %i[base_url email api_token]
      )

      expect(result).not_to be_success
      expect(result.error).to include("Email")
    end

    it "skips blank optional fields" do
      result = described_class.call(
        namespace: "email",
        fields: { smtp_host: "smtp.gmail.com", from_name: "" },
        required: %i[smtp_host]
      )

      expect(result).to be_success
      expect(VaultEntry.find_by(namespace: "email", key: "smtp_host")).to be_present
      expect(VaultEntry.find_by(namespace: "email", key: "from_name")).to be_nil
    end

    it "updates existing vault entries" do
      create(:vault_entry, namespace: "github", key: "token", value: "old_token")

      described_class.call(
        namespace: "github",
        fields: { token: "new_token" },
        required: %i[token]
      )

      expect(VaultEntry.find_by(namespace: "github", key: "token").value).to eq("new_token")
    end
  end
end
