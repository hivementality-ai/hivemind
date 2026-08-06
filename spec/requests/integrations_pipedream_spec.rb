# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Integrations Pipedream", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def configure!
    VaultEntry.create!(namespace: "pipedream", key: "client_id", encrypted_value: "cid")
    VaultEntry.create!(namespace: "pipedream", key: "client_secret", encrypted_value: "csecret")
    Setting.set("pipedream_project_id", "proj_1")
    Setting.set("pipedream_environment", "development")
    Setting.set("pipedream_external_user_id", "user-1")
  end

  describe "PATCH /integrations/pipedream" do
    it "stores credentials and generates a stable external_user_id" do
      allow_any_instance_of(Pipedream::TokenManager).to receive(:refresh_access_token!).and_return("tok")

      patch update_pipedream_path, params: {
        pipedream_client_id: "cid", pipedream_client_secret: "csecret",
        pipedream_project_id: "proj_1", pipedream_environment: "production"
      }

      expect(response).to redirect_to(integrations_path)
      expect(VaultEntry.find_by(namespace: "pipedream", key: "client_id").value).to eq("cid")
      expect(Setting.get("pipedream_project_id")).to eq("proj_1")
      expect(Setting.get("pipedream_environment")).to eq("production")
      expect(Setting.get("pipedream_external_user_id")).to be_present
    end

    it "rejects incomplete credentials" do
      patch update_pipedream_path, params: { pipedream_client_id: "cid" }
      expect(flash[:alert]).to be_present
    end
  end

  describe "POST /integrations/pipedream/apps" do
    before { configure! }

    it "creates an McpServer for the app and redirects to the Pipedream connect link" do
      allow_any_instance_of(Pipedream::TokenManager).to receive(:mint_connect_token)
        .and_return(ServiceResponse.success(data: { connect_url: "https://pipedream.com/connect/xyz?app=slack" }))

      expect {
        post enable_pipedream_app_path, params: { app_slug: "Slack" }
      }.to change(McpServer, :count).by(1)

      server = McpServer.find_by(name: "Pipedream: slack")
      expect(server.metadata["provider"]).to eq("pipedream")
      expect(server.metadata["app_slug"]).to eq("slack")
      expect(server.url).to eq(Mcp::PipedreamClient::REMOTE_MCP_URL)
      expect(response).to redirect_to("https://pipedream.com/connect/xyz?app=slack")
    end

    it "requires an app slug" do
      post enable_pipedream_app_path, params: { app_slug: "" }
      expect(response).to redirect_to(integrations_path)
      expect(flash[:alert]).to be_present
    end
  end

  describe "GET /integrations/pipedream/callback" do
    before { configure! }

    let!(:server) do
      create(:mcp_server, :sse, name: "Pipedream: slack", url: Mcp::PipedreamClient::REMOTE_MCP_URL,
        metadata: { "provider" => "pipedream", "app_slug" => "slack", "external_user_id" => "user-1" })
    end

    it "discovers tools for the connected app" do
      allow(Mcp::PipedreamClient).to receive(:discover_tools)
        .and_return(ServiceResponse.success(data: { tools: [ { "name" => "send_message" } ] }))

      get pipedream_callback_path(server_id: server.id)

      expect(response).to redirect_to(integrations_path)
      expect(flash[:notice]).to include("1 tools")
    end

    it "handles an unknown server" do
      get pipedream_callback_path(server_id: 999_999)
      expect(flash[:alert]).to be_present
    end
  end

  describe "connect/refresh routing for pipedream servers" do
    before { configure! }

    let!(:server) do
      create(:mcp_server, :sse, name: "Pipedream: slack", url: Mcp::PipedreamClient::REMOTE_MCP_URL,
        metadata: { "provider" => "pipedream", "app_slug" => "slack", "external_user_id" => "user-1" })
    end

    it "routes connect to the Pipedream client, not SseClient" do
      expect(Mcp::PipedreamClient).to receive(:discover_tools)
        .and_return(ServiceResponse.success(data: { tools: [] }))
      expect(Mcp::SseClient).not_to receive(:discover_tools)

      post connect_mcp_server_path(server)
      expect(response).to redirect_to(integrations_path)
    end
  end
end
