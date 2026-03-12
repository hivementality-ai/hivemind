# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Integrations MCP Servers", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "POST /integrations/mcp_servers" do
    it "creates a new MCP server" do
      post create_mcp_server_path, params: { mcp_server: { name: "Test Server", transport: "stdio", command: "npx test" } }
      expect(response).to redirect_to(integrations_path)
      expect(McpServer.find_by(name: "Test Server")).to be_present
    end

    it "shows errors for invalid server" do
      post create_mcp_server_path, params: { mcp_server: { name: "", transport: "stdio" } }
      expect(response).to redirect_to(integrations_path)
      expect(flash[:alert]).to be_present
    end
  end

  describe "PATCH /integrations/mcp_servers/:id" do
    let!(:server) { create(:mcp_server) }

    it "updates an MCP server" do
      patch update_mcp_server_path(server), params: { mcp_server: { name: "Updated Name" } }
      expect(response).to redirect_to(integrations_path)
      expect(server.reload.name).to eq("Updated Name")
    end
  end

  describe "DELETE /integrations/mcp_servers/:id" do
    let!(:server) { create(:mcp_server) }

    it "destroys an MCP server" do
      expect { delete destroy_mcp_server_path(server) }.to change(McpServer, :count).by(-1)
      expect(response).to redirect_to(integrations_path)
    end
  end

  describe "POST /integrations/mcp_servers/:id/connect" do
    let!(:server) { create(:mcp_server, :sse) }

    it "connects to an SSE server" do
      allow(Mcp::SseClient).to receive(:discover_tools).and_return(ServiceResponse.success(data: { tools: [] }))
      post connect_mcp_server_path(server)
      expect(response).to redirect_to(integrations_path)
    end
  end

  describe "POST /integrations/mcp_servers/:id/disconnect" do
    let!(:server) { create(:mcp_server, :sse, :connected) }

    it "disconnects from an SSE server" do
      post disconnect_mcp_server_path(server)
      expect(response).to redirect_to(integrations_path)
      expect(server.reload.status).to eq("disconnected")
    end
  end

  describe "GET /integrations/mcp_servers/:id/refresh" do
    let!(:server) { create(:mcp_server, :sse, :connected) }

    it "refreshes tools" do
      tools = [ { "name" => "test", "description" => "A tool" } ]
      allow(Mcp::SseClient).to receive(:discover_tools).and_return(ServiceResponse.success(data: { tools: tools }))
      get refresh_mcp_tools_path(server)
      expect(response).to redirect_to(integrations_path)
    end
  end

  describe "PATCH /integrations/mcp_servers/:id/toggle" do
    let!(:server) { create(:mcp_server, enabled: true) }

    it "toggles server enabled state" do
      patch toggle_mcp_server_path(server)
      expect(response).to redirect_to(integrations_path)
      expect(server.reload.enabled).to be false
    end
  end
end
