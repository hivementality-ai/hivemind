# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pipedream::TokenManager, type: :service do
  let(:client) { described_class.new }

  before do
    allow(VaultEntry).to receive(:find_by)
      .with(namespace: "pipedream", key: "client_id")
      .and_return(instance_double(VaultEntry, value: "pd-client-id"))
    allow(VaultEntry).to receive(:find_by)
      .with(namespace: "pipedream", key: "client_secret")
      .and_return(instance_double(VaultEntry, value: "pd-client-secret"))
    allow(Setting).to receive(:get)
      .with("pipedream_project_id")
      .and_return("pd-project-123")
    allow(Setting).to receive(:get)
      .with("pipedream_environment")
      .and_return("development")
  end

  describe "#configured?" do
    it "returns true when all credentials are set" do
      expect(client.configured?).to be true
    end

    it "returns false when client ID is missing" do
      allow(VaultEntry).to receive(:find_by)
        .with(namespace: "pipedream", key: "client_id")
        .and_return(nil)
      expect(described_class.new.configured?).to be false
    end

    it "returns false when client secret is missing" do
      allow(VaultEntry).to receive(:find_by)
        .with(namespace: "pipedream", key: "client_secret")
        .and_return(nil)
      expect(described_class.new.configured?).to be false
    end

    it "returns false when project ID is missing" do
      allow(Setting).to receive(:get)
        .with("pipedream_project_id")
        .and_return(nil)
      expect(described_class.new.configured?).to be false
    end
  end

  describe "#access_token" do
    let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

    before do
      allow(Rails).to receive(:cache).and_return(memory_cache)
    end

    after do
      memory_cache.clear
    end

    it "fetches and caches access token on first call" do
      stub_request(:post, "https://api.pipedream.com/v1/oauth/token")
        .to_return(status: 200, body: {
          access_token: "pd-access-token-abc",
          expires_in: 3600
        }.to_json)

      token = client.access_token

      expect(token).to eq("pd-access-token-abc")
      expect(memory_cache.read("pipedream:access_token")).to eq("pd-access-token-abc")
    end

    it "returns cached token on subsequent calls" do
      memory_cache.write("pipedream:access_token", "cached-token", expires_in: 55.minutes)

      stub_request(:post, "https://api.pipedream.com/v1/oauth/token")
        .to_return(status: 200, body: { access_token: "fresh-token", expires_in: 3600 }.to_json)

      token = client.access_token
      expect(token).to eq("cached-token")
      expect(WebMock).not_to have_requested(:post, "https://api.pipedream.com/v1/oauth/token")
    end

    it "returns nil when not configured" do
      allow(VaultEntry).to receive(:find_by)
        .with(namespace: "pipedream", key: "client_id")
        .and_return(nil)

      expect(client.access_token).to be_nil
    end

    it "returns nil when token fetch fails" do
      stub_request(:post, "https://api.pipedream.com/v1/oauth/token")
        .to_return(status: 400, body: { error: "invalid_client" }.to_json)

      expect(client.access_token).to be_nil
    end
  end

  describe "#refresh_access_token!" do
    let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

    before do
      allow(Rails).to receive(:cache).and_return(memory_cache)
    end

    after do
      memory_cache.clear
    end

    it "deletes cached token and fetches new one" do
      memory_cache.write("pipedream:access_token", "old-token", expires_in: 55.minutes)

      stub_request(:post, "https://api.pipedream.com/v1/oauth/token")
        .to_return(status: 200, body: { access_token: "new-token", expires_in: 3600 }.to_json)

      token = client.refresh_access_token!

      expect(token).to eq("new-token")
      expect(memory_cache.read("pipedream:access_token")).to eq("new-token")
    end
  end

  describe "#mint_connect_token" do
    let(:external_user_id) { "user-123" }
    let(:app_slug) { "slack" }
    let(:success_redirect_uri) { "https://example.com/integrations/pipedream/callback?server_id=1" }
    let(:connect_tokens_url) { "https://api.pipedream.com/v1/connect/pd-project-123/tokens" }

    before do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      stub_request(:post, "https://api.pipedream.com/v1/oauth/token")
        .to_return(status: 200, body: { access_token: "pd-access-token", expires_in: 3600 }.to_json)
    end

    it "mints a connect token and returns the hosted connect URL with the app preselected" do
      stub_request(:post, connect_tokens_url)
        .to_return(status: 200, body: {
          token: "ctok_#{'a' * 32}",
          expires_at: "2026-07-15T12:00:00Z",
          connect_link_url: "https://pipedream.com/_static/connect.html?token=ctok_x&connectLink=true"
        }.to_json)

      result = client.mint_connect_token(
        external_user_id: external_user_id,
        app_slug: app_slug,
        success_redirect_uri: success_redirect_uri
      )

      expect(result).to be_success
      expect(result.data[:token]).to start_with("ctok_")
      expect(result.data[:connect_url]).to include("pipedream.com/_static/connect.html")
      expect(result.data[:connect_url]).to include("app=slack")
      expect(WebMock).to have_requested(:post, connect_tokens_url)
        .with(headers: { "Authorization" => "Bearer pd-access-token", "x-pd-environment" => "development" },
              body: hash_including("external_user_id" => "user-123"))
    end

    it "returns failure when not configured" do
      allow(VaultEntry).to receive(:find_by)
        .with(namespace: "pipedream", key: "client_id")
        .and_return(nil)

      result = described_class.new.mint_connect_token(
        external_user_id: external_user_id, app_slug: app_slug, success_redirect_uri: success_redirect_uri
      )

      expect(result).not_to be_success
      expect(result.error).to eq("Not configured")
    end

    it "returns failure when the connect token request fails" do
      stub_request(:post, connect_tokens_url)
        .to_return(status: 400, body: { error: "bad_request", message: "Invalid project" }.to_json)

      result = client.mint_connect_token(
        external_user_id: external_user_id, app_slug: app_slug, success_redirect_uri: success_redirect_uri
      )

      expect(result).not_to be_success
      expect(result.error).to include("bad_request")
    end

    it "handles network errors gracefully" do
      stub_request(:post, connect_tokens_url).to_raise(Errno::ECONNREFUSED)

      result = client.mint_connect_token(
        external_user_id: external_user_id, app_slug: app_slug, success_redirect_uri: success_redirect_uri
      )

      expect(result).not_to be_success
      expect(result.error).to include("Connect token mint failed")
    end
  end

  describe "cache key and TTL constants" do
    it "uses the correct cache key" do
      expect(described_class::ACCESS_TOKEN_CACHE_KEY).to eq("pipedream:access_token")
    end

    it "uses 55 minute TTL for access tokens" do
      expect(described_class::ACCESS_TOKEN_TTL).to eq(55.minutes)
    end
  end
end
