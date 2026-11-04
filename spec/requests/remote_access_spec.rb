# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Remote access", type: :request do
  after { RemoteAccess::ConfigStore.clear! }

  describe "authorization" do
    it "denies viewers" do
      sign_in create(:user, :viewer)
      get remote_access_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Access denied.")
    end

    it "denies operators" do
      sign_in create(:user, :operator)
      get remote_access_path
      expect(response).to redirect_to(root_path)
    end

    it "allows admins" do
      sign_in create(:user, :admin)
      get remote_access_path
      expect(response).to have_http_status(:ok)
    end

    it "allows owners" do
      sign_in create(:user, :owner)
      get remote_access_path
      expect(response).to have_http_status(:ok)
    end

    it "redirects anonymous users to sign in" do
      get remote_access_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "the wizard vs status card" do
    before { sign_in create(:user, :owner) }

    it "renders the wizard when unconfigured" do
      get remote_access_path
      expect(response.body).to include("I already have a tunnel")
      expect(response.body).to include("Guide me")
    end

    it "renders the status card once configured" do
      RemoteAccess::ConfigStore.canonical_host = "https://hivemind.example.com"
      RemoteAccess::ConfigStore.mode = "byo"

      get remote_access_path
      expect(response.body).to include("hivemind.example.com")
      expect(response.body).not_to include("I already have a tunnel")
    end
  end

  describe "POST /remote_access/verify_byo (Path A: bring-your-own tunnel)" do
    before { sign_in create(:user, :owner) }

    it "verifies and persists the URL when both checks pass" do
      allow(RemoteAccess::HealthCheck).to receive(:call)
        .with("https://hivemind.example.com")
        .and_return(ServiceResponse.success(data: { http: { ok: true, status: 200 }, websocket: { ok: true } }))

      post verify_byo_remote_access_path, params: { public_url: "https://hivemind.example.com" }

      expect(response).to redirect_to(remote_access_path)
      expect(RemoteAccess::ConfigStore.canonical_host).to eq("https://hivemind.example.com")
      expect(RemoteAccess::ConfigStore.mode).to eq("byo")
    end

    it "does not persist the URL when the HTTP check fails" do
      checks = { http: { ok: false, error: "connection refused" }, websocket: { ok: true } }
      allow(RemoteAccess::HealthCheck).to receive(:call)
        .and_return(ServiceResponse.failure(error: "HTTP check failed: connection refused", payload: checks))

      post verify_byo_remote_access_path, params: { public_url: "https://broken.example.com" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(RemoteAccess::ConfigStore.canonical_host).to be_nil
      expect(response.body).to include("connection refused")
    end

    it "does not persist the URL when the WebSocket check fails" do
      checks = { http: { ok: true, status: 200 }, websocket: { ok: false, error: "handshake timed out" } }
      allow(RemoteAccess::HealthCheck).to receive(:call)
        .and_return(ServiceResponse.failure(error: "WebSocket check failed: handshake timed out", payload: checks))

      post verify_byo_remote_access_path, params: { public_url: "https://no-cable.example.com" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(RemoteAccess::ConfigStore.canonical_host).to be_nil
    end
  end

  describe "POST /remote_access/provision_cloudflare (Path B: guided Cloudflare)" do
    before { sign_in create(:user, :owner) }

    it "provisions the tunnel, starts the connector, verifies, and sets canonical host" do
      provision_result = ServiceResponse.success(data: {
        account_id: "acct123",
        zone_id: "zone123",
        tunnel_id: "tunnel123",
        tunnel_token: "tok_abc",
        hostname: "hivemind.example.com",
        public_url: "https://hivemind.example.com"
      })
      allow_any_instance_of(Cloudflare::TunnelProvisioner).to receive(:provision).and_return(provision_result)
      allow(RemoteAccess::ConnectorManager).to receive(:start).and_return(ServiceResponse.success(data: { output: "started" }))
      allow(RemoteAccess::HealthCheck).to receive(:call)
        .with("https://hivemind.example.com")
        .and_return(ServiceResponse.success(data: { http: { ok: true, status: 200 }, websocket: { ok: true } }))

      post provision_cloudflare_remote_access_path, params: { cloudflare_api_token: "cf-token", hostname: "hivemind.example.com" }

      expect(response).to redirect_to(remote_access_path)
      expect(RemoteAccess::ConfigStore.canonical_host).to eq("https://hivemind.example.com")
      expect(RemoteAccess::ConfigStore.mode).to eq("cloudflare")
      expect(RemoteAccess::ConfigStore.cloudflare_tunnel_id).to eq("tunnel123")
    end

    it "does not set canonical host when provisioning fails" do
      allow_any_instance_of(Cloudflare::TunnelProvisioner).to receive(:provision)
        .and_return(ServiceResponse.failure(error: "No Cloudflare zone found for hivemind.example.com"))

      post provision_cloudflare_remote_access_path, params: { cloudflare_api_token: "cf-token", hostname: "hivemind.example.com" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(RemoteAccess::ConfigStore.canonical_host).to be_nil
    end

    it "requires both a token and a hostname" do
      post provision_cloudflare_remote_access_path, params: { cloudflare_api_token: "", hostname: "" }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "status card actions" do
    before do
      sign_in create(:user, :owner)
      RemoteAccess::ConfigStore.canonical_host = "https://hivemind.example.com"
      RemoteAccess::ConfigStore.mode = "byo"
    end

    it "re-verifies and updates status" do
      allow(RemoteAccess::HealthCheck).to receive(:call)
        .and_return(ServiceResponse.success(data: { http: { ok: true, status: 200 }, websocket: { ok: true } }))

      post re_verify_remote_access_path
      expect(response).to redirect_to(remote_access_path)
      expect(RemoteAccess::ConfigStore.http_ok?).to eq(true)
      expect(RemoteAccess::ConfigStore.websocket_ok?).to eq(true)
    end

    it "clears configuration on reconfigure" do
      post reconfigure_remote_access_path
      expect(RemoteAccess::ConfigStore.canonical_host).to be_nil
    end

    it "clears configuration on disconnect" do
      delete remote_access_path
      expect(RemoteAccess::ConfigStore.canonical_host).to be_nil
    end

    it "restarts the connector for the cloudflare path" do
      RemoteAccess::ConfigStore.mode = "cloudflare"
      allow(RemoteAccess::ConnectorManager).to receive(:restart).and_return(ServiceResponse.success(data: { output: "restarted" }))

      post restart_connector_remote_access_path
      expect(response).to redirect_to(remote_access_path)
    end
  end
end
