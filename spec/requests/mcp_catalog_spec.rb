# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP starter catalog", type: :request do
  let(:notion_url) { "https://mcp.notion.com/mcp" }

  describe "the catalog file" do
    it "lists https servers with a summary and docs link" do
      expect(Mcp::Catalog.entries.map(&:name)).to include("Notion", "Linear", "Atlassian", "Asana", "Stripe", "Sentry")
      Mcp::Catalog.entries.each do |entry|
        expect(entry.url).to start_with("https://")
        expect(entry.summary).to be_present
        expect(entry.docs).to start_with("https://")
      end
    end
  end

  describe "cards on the Integrations page" do
    before { sign_in create(:user, :owner) }

    it "shows an Add button for each server that is not added yet" do
      get integrations_path

      expect(response.body).to include("Search, read and update your Notion pages and databases.")
      expect(response.body).to include(add_from_catalog_mcp_servers_path(key: "notion"))
    end

    it "shows Connect for an added server that is not signed in" do
      server = create(:mcp_server, :sse, name: "Notion", url: notion_url)

      get integrations_path

      expect(response.body).to include(oauth_connect_mcp_server_path(server))
      expect(response.body).not_to include(add_from_catalog_mcp_servers_path(key: "notion"))
    end

    it "shows Connected for a server that is connected" do
      create(:mcp_server, :sse, :connected, name: "Notion", url: notion_url)

      get integrations_path

      expect(response.body).to match(%r{data-catalog="notion".*?Connected}m)
    end
  end

  describe "POST /mcp_servers/catalog/:key" do
    let(:meta) do
      { issuer: "https://auth.example.com", authorization_endpoint: "https://auth.example.com/authorize",
        token_endpoint: "https://auth.example.com/token", registration_endpoint: "https://auth.example.com/register" }
    end

    before do
      sign_in create(:user, :owner)
      stub_request(:post, notion_url).with { |r| JSON.parse(r.body)["method"] == "initialize" }
        .to_return(status: 401, headers: { "WWW-Authenticate" => 'Bearer resource_metadata="https://mcp.notion.com/prm"' })
      stub_request(:get, "https://mcp.notion.com/prm").to_return(body: { authorization_servers: [ "https://auth.example.com" ] }.to_json)
      stub_request(:get, "https://auth.example.com/.well-known/oauth-authorization-server").to_return(body: meta.to_json)
      stub_request(:post, meta[:registration_endpoint]).to_return(status: 201, body: { client_id: "cid" }.to_json)
    end

    it "creates the server and redirects into the OAuth flow" do
      expect { post add_from_catalog_mcp_servers_path(key: "notion") }.to change(McpServer, :count).by(1)

      expect(McpServer.last).to have_attributes(name: "Notion", url: notion_url, transport: "http")
      expect(response.location).to start_with("https://auth.example.com/authorize?")
    end

    it "reuses the server when it was already added" do
      create(:mcp_server, :sse, name: "Notion", url: notion_url)

      expect { post add_from_catalog_mcp_servers_path(key: "notion") }.not_to change(McpServer, :count)
      expect(response.location).to start_with("https://auth.example.com/authorize?")
    end

    it "adds under a free name when a different server already uses the name" do
      existing = create(:mcp_server, :sse, name: "Notion", url: "https://example.com/sse")
      create(:mcp_server, :sse, name: "Notion (catalog)", url: "https://example.com/other")

      expect { post add_from_catalog_mcp_servers_path(key: "notion") }.to change(McpServer, :count).by(1)

      expect(McpServer.find_by(name: "Notion (catalog) 2")).to have_attributes(url: notion_url)
      expect(existing.reload).to have_attributes(name: "Notion", url: "https://example.com/sse")
      expect(response.location).to start_with("https://auth.example.com/authorize?")
    end

    it "rejects a key that is not in the catalog" do
      expect { post add_from_catalog_mcp_servers_path(key: "nope") }.not_to change(McpServer, :count)
      expect(response).to redirect_to(integrations_path)
    end
  end
end
