# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::ConnectionTester, type: :service do
  describe ".call" do
    context "with unknown provider" do
      it "returns failure" do
        result = described_class.call(:nonexistent)
        expect(result).not_to be_success
        expect(result.error).to include("Unknown provider")
      end
    end

    context "with github" do
      before do
        create(:vault_entry, namespace: "github", key: "token", value: "ghp_test123")
      end

      it "returns failure when not configured" do
        VaultEntry.destroy_all
        result = described_class.call(:github)
        expect(result).not_to be_success
        expect(result.error).to include("not configured")
      end

      it "returns success when API responds" do
        stub_request(:get, "https://api.github.com/user")
          .to_return(status: 200, body: { login: "testuser", name: "Test User" }.to_json)

        result = described_class.call(:github)
        expect(result).to be_success
        expect(result.data[:user]).to eq("testuser")
      end

      it "returns failure on HTTP error" do
        stub_request(:get, "https://api.github.com/user")
          .to_return(status: 401)

        result = described_class.call(:github)
        expect(result).not_to be_success
        expect(result.error).to include("401")
      end
    end

    context "with jira" do
      before do
        create(:vault_entry, namespace: "jira", key: "base_url", value: "https://test.atlassian.net")
        create(:vault_entry, namespace: "jira", key: "email", value: "user@test.com")
        create(:vault_entry, namespace: "jira", key: "api_token", value: "jira_token")
      end

      it "returns success when API responds" do
        stub_request(:get, "https://test.atlassian.net/rest/api/3/myself")
          .to_return(status: 200, body: { displayName: "Test User", emailAddress: "user@test.com" }.to_json)

        result = described_class.call(:jira)
        expect(result).to be_success
        expect(result.data[:user]).to eq("Test User")
      end
    end
  end
end
