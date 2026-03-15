# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleWorkspace::OAuthClient, type: :service do
  let(:client) { described_class.new }

  before do
    allow(VaultEntry).to receive(:find_by)
      .with(namespace: "google_workspace", key: "client_id")
      .and_return(instance_double(VaultEntry, value: "test-client-id"))
    allow(VaultEntry).to receive(:find_by)
      .with(namespace: "google_workspace", key: "client_secret")
      .and_return(instance_double(VaultEntry, value: "test-client-secret"))
  end

  describe "#configured?" do
    it "returns true when credentials are set" do
      expect(client.configured?).to be true
    end

    it "returns false when client ID is missing" do
      allow(VaultEntry).to receive(:find_by)
        .with(namespace: "google_workspace", key: "client_id")
        .and_return(nil)
      expect(described_class.new.configured?).to be false
    end
  end

  describe "#authorization_url" do
    it "builds a valid Google OAuth URL" do
      url = client.authorization_url(
        redirect_uri: "https://example.com/callback",
        state: "test-state"
      )

      expect(url).to start_with("https://accounts.google.com/o/oauth2/v2/auth")
      expect(url).to include("client_id=test-client-id")
      expect(url).to include("state=test-state")
      expect(url).to include("access_type=offline")
      expect(url).to include("drive")
      expect(url).to include("calendar")
    end

    it "includes requested scopes" do
      url = client.authorization_url(
        redirect_uri: "https://example.com/callback",
        state: "test",
        scopes: %i[drive calendar gmail]
      )

      expect(url).to include("gmail.modify")
    end
  end

  describe "#exchange_code" do
    it "exchanges auth code for tokens" do
      stub_request(:post, "https://oauth2.googleapis.com/token")
        .to_return(status: 200, body: {
          access_token: "ya29.test",
          refresh_token: "1//test-refresh",
          expires_in: 3600,
          scope: "https://www.googleapis.com/auth/drive"
        }.to_json)

      result = client.exchange_code(code: "auth-code", redirect_uri: "https://example.com/callback")
      expect(result).to be_success
      expect(result.data[:access_token]).to eq("ya29.test")
      expect(result.data[:refresh_token]).to eq("1//test-refresh")
    end

    it "returns failure on OAuth error" do
      stub_request(:post, "https://oauth2.googleapis.com/token")
        .to_return(status: 400, body: {
          error: "invalid_grant",
          error_description: "Code expired"
        }.to_json)

      result = client.exchange_code(code: "bad-code", redirect_uri: "https://example.com/callback")
      expect(result).not_to be_success
      expect(result.error).to include("Code expired")
    end
  end

  describe "#refresh_token" do
    it "refreshes an access token" do
      stub_request(:post, "https://oauth2.googleapis.com/token")
        .to_return(status: 200, body: {
          access_token: "ya29.refreshed",
          expires_in: 3600
        }.to_json)

      result = client.refresh_token("1//test-refresh")
      expect(result).to be_success
      expect(result.data[:access_token]).to eq("ya29.refreshed")
    end
  end

  describe "#fetch_user_info" do
    it "returns user email and name" do
      stub_request(:get, "https://www.googleapis.com/oauth2/v3/userinfo")
        .to_return(status: 200, body: {
          email: "user@example.com",
          name: "Test User"
        }.to_json)

      result = client.fetch_user_info("ya29.test")
      expect(result).to be_success
      expect(result.data[:email]).to eq("user@example.com")
    end
  end
end
