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

    describe "agent assignment" do
      let!(:alpha) { create(:agent, name: "Alpha") }
      let!(:beta) { create(:agent, name: "Beta") }
      let!(:system_agent) { create(:agent, name: "Sysbot", system_agent: true) }

      it "lists visible agents on the new form, all checked, and on the edit form with the assigned ones checked" do
        get new_mcp_server_path
        expect(response.body).to match(/value="#{alpha.id}"[^>]*checked/)
        expect(response.body).to match(/value="#{beta.id}"[^>]*checked/)
        expect(response.body).not_to include("Sysbot")

        server = create(:mcp_server)
        create(:agent_mcp_server, agent: beta, mcp_server: server)
        get edit_mcp_server_path(server)
        expect(response.body).not_to match(/value="#{alpha.id}"[^>]*checked/)
        expect(response.body).to match(/value="#{beta.id}"[^>]*checked/)
      end

      it "assigns the ticked agents on create" do
        post mcp_servers_path, params: { mcp_server: { name: "Files", transport: "stdio", command: "npx files", agent_ids: [ "", alpha.id.to_s ] } }

        expect(McpServer.find_by!(name: "Files").agents).to eq([ alpha ])
      end

      it "assigns every visible agent on create when the form sends no picker" do
        post mcp_servers_path, params: { mcp_server: { name: "Files", transport: "stdio", command: "npx files" } }

        expect(McpServer.find_by!(name: "Files").agents).to match_array([ alpha, beta ])
      end

      it "replaces the visible assignments on update and can clear them all" do
        server = create(:mcp_server)
        create(:agent_mcp_server, agent: alpha, mcp_server: server)
        create(:agent_mcp_server, agent: system_agent, mcp_server: server)

        patch mcp_server_path(server), params: { mcp_server: { name: server.name, agent_ids: [ "", beta.id.to_s ] } }
        expect(server.reload.agents).to match_array([ beta, system_agent ])

        patch mcp_server_path(server), params: { mcp_server: { name: server.name, agent_ids: [ "" ] } }
        expect(server.reload.agents).to eq([ system_agent ])
      end

      it "keeps assignments when an update sends no picker" do
        server = create(:mcp_server)
        create(:agent_mcp_server, agent: alpha, mcp_server: server)

        patch mcp_server_path(server), params: { mcp_server: { name: "Renamed" } }

        expect(server.reload.agents).to eq([ alpha ])
      end
    end

    describe "manual OAuth client" do
      it "keeps the id on the row and the secret in the vault" do
        post mcp_servers_path, params: { mcp_server: { name: "Remote", transport: "http", url: "https://mcp.example.com",
                                                        oauth_client_id: "my-id", oauth_client_secret: "s3cret" } }

        server = McpServer.find_by!(name: "Remote")
        expect(server.metadata).to eq("oauth_client_id" => "my-id", "oauth_client_secret" => "vault:mcp_remote/oauth_client_secret")
        expect(server.oauth_client_secret).to eq("s3cret")
        expect(server.to_json).not_to include("s3cret")
      end

      it "keeps the stored secret when the field is left blank and clears both when the id is emptied" do
        server = create(:mcp_server, :sse, name: "Remote")
        patch mcp_server_path(server), params: { mcp_server: { name: "Remote", oauth_client_id: "my-id", oauth_client_secret: "s3cret" } }
        patch mcp_server_path(server), params: { mcp_server: { name: "Remote", oauth_client_id: "my-id", oauth_client_secret: "" } }
        expect(server.reload.oauth_client_secret).to eq("s3cret")

        patch mcp_server_path(server), params: { mcp_server: { name: "Remote", oauth_client_id: "", oauth_client_secret: "" } }
        expect(server.reload.metadata).to eq({})
      end

      it "shows the id but never the secret on the edit form" do
        server = create(:mcp_server, :sse, name: "Remote")
        patch mcp_server_path(server), params: { mcp_server: { name: "Remote", oauth_client_id: "my-id", oauth_client_secret: "s3cret" } }

        get edit_mcp_server_path(server)

        expect(response.body).to include("my-id")
        expect(response.body).not_to include("s3cret")
      end
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

    describe "OAuth" do
      let(:url) { "https://mcp.example.com/mcp" }
      let(:server) { create(:mcp_server, :sse, url: url, status: "error", last_error: "HTTP 401: nope") }
      let(:meta) do
        { issuer: "https://auth.example.com", authorization_endpoint: "https://auth.example.com/authorize",
          token_endpoint: "https://auth.example.com/token", registration_endpoint: "https://auth.example.com/register" }
      end

      before do
        stub_request(:post, url).with { |r| JSON.parse(r.body)["method"] == "initialize" && r.headers["Authorization"].blank? }
          .to_return(status: 401, headers: { "WWW-Authenticate" => 'Bearer resource_metadata="https://mcp.example.com/prm"' })
        stub_request(:get, "https://mcp.example.com/prm").to_return(body: { authorization_servers: [ "https://auth.example.com" ] }.to_json)
        stub_request(:get, "https://auth.example.com/.well-known/oauth-authorization-server").to_return(body: meta.to_json)
        stub_request(:post, meta[:registration_endpoint]).to_return(status: 201, body: { client_id: "cid" }.to_json)
      end

      def start_flow
        post oauth_connect_mcp_server_path(server)
        Rack::Utils.parse_query(URI.parse(response.location).query)
      end

      it "shows Connect for a remote server that answered 401" do
        server
        get mcp_servers_path

        expect(response.body).to include(oauth_connect_mcp_server_path(server))
      end

      it "redirects to the authorization server with the request host as redirect uri" do
        params = start_flow

        expect(response.location).to start_with("https://auth.example.com/authorize?")
        expect(params["redirect_uri"]).to eq("http://www.example.com#{oauth_callback_mcp_server_path(server)}")
      end

      it "prefers the configured canonical host for the redirect uri" do
        Setting.set("canonical_host", "https://hive.example.com/")

        expect(start_flow["redirect_uri"]).to eq("https://hive.example.com#{oauth_callback_mcp_server_path(server)}")
      end

      it "completes the flow on callback, stores tokens in the vault and discovers tools" do
        state = start_flow["state"]
        stub_request(:post, meta[:token_endpoint]).to_return(body: { access_token: "at", refresh_token: "rt" }.to_json)
        allow(Mcp::HttpClient).to receive(:discover_tools).with(server)
          .and_return(ServiceResponse.success(data: { tools: [ { "name" => "a" } ] }))

        get oauth_callback_mcp_server_path(server), params: { code: "abc", state: state }

        expect(response).to redirect_to(mcp_servers_path)
        expect(flash[:notice]).to include("Connected")
        expect(Mcp::OAuth.headers_for(server)).to eq("Authorization" => "Bearer at")
      end

      it "rejects a callback with a bad state and stores nothing" do
        start_flow
        token = stub_request(:post, meta[:token_endpoint])

        get oauth_callback_mcp_server_path(server), params: { code: "abc", state: "forged" }

        expect(response).to redirect_to(mcp_servers_path)
        expect(flash[:alert]).to include("Invalid state")
        expect(token).not_to have_been_requested
        expect(Mcp::OAuth).not_to be_connected(server)
      end

      it "reports an authorization error from the provider" do
        get oauth_callback_mcp_server_path(server), params: { error: "access_denied" }

        expect(flash[:alert]).to include("access_denied")
      end

      it "signs out by deleting the stored credentials" do
        state = start_flow["state"]
        stub_request(:post, meta[:token_endpoint]).to_return(body: { access_token: "at" }.to_json)
        allow(Mcp::HttpClient).to receive(:discover_tools).and_return(ServiceResponse.success(data: { tools: [] }))
        get oauth_callback_mcp_server_path(server), params: { code: "abc", state: state }

        delete oauth_disconnect_mcp_server_path(server)

        expect(Mcp::OAuth).not_to be_connected(server)
        expect(VaultEntry.where(namespace: "mcp_oauth_#{server.id}")).to be_empty
      end

      it "refuses stdio servers" do
        post oauth_connect_mcp_server_path(create(:mcp_server, :stdio))

        expect(response).to redirect_to(mcp_servers_path)
        expect(flash[:alert]).to include("remote")
      end

      it "deletes stored credentials with the server" do
        VaultEntry.create!(namespace: "mcp_oauth_#{server.id}", key: "tokens", value: "{}")

        expect { delete mcp_server_path(server) }.to change(VaultEntry, :count).by(-1)
      end
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
