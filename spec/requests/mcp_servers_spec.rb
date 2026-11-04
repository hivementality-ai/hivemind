# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP servers", type: :request do
  describe "as an owner" do
    before { sign_in create(:user, :owner) }

    it "lists servers with status and tool count" do
      create(:mcp_server, :stdio, :connected, :with_tools, name: "Files")

      get mcp_servers_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Files", "connected")
    end

    it "renders the new and edit forms" do
      server = create(:mcp_server)

      get new_mcp_server_path
      expect(response).to have_http_status(:ok)
      get edit_mcp_server_path(server)
      expect(response).to have_http_status(:ok)
    end

    it "creates a stdio server" do
      post mcp_servers_path, params: { mcp_server: { name: "Files", transport: "stdio", command: "npx files", enabled: "1" } }

      expect(response).to redirect_to(mcp_servers_path)
      expect(McpServer.find_by(name: "Files")).to have_attributes(command: "npx files", enabled: true)
    end

    it "moves secret env values and header values into the vault" do
      post mcp_servers_path, params: { mcp_server: {
        name: "Remote", transport: "http", url: "https://mcp.example.com",
        env_vars_text: "API_TOKEN=abc123\nREGION=eu",
        auth_config_text: "Authorization=Bearer xyz"
      } }

      server = McpServer.find_by!(name: "Remote")
      expect(server.env_vars).to eq("API_TOKEN" => "vault:mcp_remote/env_api_token", "REGION" => "eu")
      expect(server.auth_config).to eq("Authorization" => "vault:mcp_remote/auth_authorization")
      expect(server.resolved_auth_headers).to eq("Authorization" => "Bearer xyz")
    end

    it "leaves no vault entry behind when the create fails validation" do
      expect do
        post mcp_servers_path, params: { mcp_server: { name: "Bad", transport: "stdio", command: "", env_vars_text: "API_TOKEN=abc" } }
      end.not_to change(VaultEntry, :count)
    end

    it "keeps existing vault references when editing" do
      server = create(:mcp_server, env_vars: { "API_TOKEN" => "vault:mcp_x/env_api_token" })

      patch mcp_server_path(server), params: { mcp_server: { name: server.name, env_vars_text: "API_TOKEN=vault:mcp_x/env_api_token" } }

      expect(server.reload.env_vars).to eq("API_TOKEN" => "vault:mcp_x/env_api_token")
    end

    it "re-renders when the server is invalid" do
      post mcp_servers_path, params: { mcp_server: { name: "Bad", transport: "stdio", command: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(McpServer.find_by(name: "Bad")).to be_nil
    end

    it "updates a server" do
      server = create(:mcp_server)

      patch mcp_server_path(server), params: { mcp_server: { name: "Renamed", command: "other" } }

      expect(response).to redirect_to(mcp_servers_path)
      expect(server.reload).to have_attributes(name: "Renamed", command: "other")
    end

    it "toggles enabled and closes the running session when disabling" do
      server = create(:mcp_server, enabled: true)
      allow(Mcp::StdioRegistry).to receive(:close)

      patch toggle_enabled_mcp_server_path(server)
      expect(server.reload.enabled).to be(false)
      expect(Mcp::StdioRegistry).to have_received(:close).with(server)

      patch toggle_enabled_mcp_server_path(server)
      expect(server.reload.enabled).to be(true)
    end

    it "deletes a server" do
      server = create(:mcp_server)

      expect { delete mcp_server_path(server) }.to change(McpServer, :count).by(-1)
      expect(response).to redirect_to(mcp_servers_path)
    end

    describe "POST test_connection" do
      it "reports the tool count for a stdio server" do
        server = create(:mcp_server, :stdio)
        allow(Mcp::StdioClient).to receive(:discover_tools).with(server)
          .and_return(ServiceResponse.success(data: { tools: [ { "name" => "a" }, { "name" => "b" } ] }))

        post test_connection_mcp_server_path(server)

        expect(flash[:notice]).to include("Found 2 tools")
      end

      it "uses the HTTP client for a remote server and singularizes one tool" do
        server = create(:mcp_server, :sse)
        allow(Mcp::HttpClient).to receive(:discover_tools).with(server)
          .and_return(ServiceResponse.success(data: { tools: [ { "name" => "a" } ] }))

        post test_connection_mcp_server_path(server)

        expect(flash[:notice]).to include("Found 1 tool.")
      end

      it "reports the error in plain words" do
        server = create(:mcp_server, :stdio)
        allow(Mcp::StdioClient).to receive(:discover_tools)
          .and_return(ServiceResponse.failure(error: "command not found"))

        post test_connection_mcp_server_path(server)

        expect(flash[:alert]).to include("Could not connect", "command not found")
      end
    end
  end

  describe "as a regular member" do
    it "denies access" do
      sign_in create(:user)

      get mcp_servers_path

      expect(response).to redirect_to(root_path)
    end
  end

  it "requires sign in" do
    get mcp_servers_path

    expect(response).to have_http_status(:redirect)
  end
end
