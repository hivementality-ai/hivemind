# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Deployers::McpServersDeployer do
  def build_document(mcp_servers: [])
    Swarms::SwarmDocument.new(
      swarm_version: "1.0",
      name:          "Test Swarm",
      mcp_servers:   mcp_servers
    )
  end

  # ---------------------------------------------------------------------------
  # Result contract
  # ---------------------------------------------------------------------------

  describe "result contract" do
    it "always returns a successful ServiceResponse" do
      result = described_class.call(document: build_document)
      expect(result).to be_success
    end

    it "returns an empty mcp_servers array when the document has no servers" do
      result = described_class.call(document: build_document(mcp_servers: []))
      expect(result.payload[:mcp_servers]).to eq([])
    end

    it "returns one DeployResult per server in the document" do
      doc = build_document(mcp_servers: [
        { "name" => "server-a", "transport" => "stdio", "command" => "npx server-a" },
        { "name" => "server-b", "transport" => "sse",   "url"     => "https://server-b.example.com" }
      ])
      result = described_class.call(document: doc)
      expect(result.payload[:mcp_servers].size).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # No conflict — create
  # ---------------------------------------------------------------------------

  describe "when no platform MCP server exists with that name" do
    it "creates a new McpServer record" do
      doc = build_document(mcp_servers: [{ "name" => "my-server", "transport" => "stdio", "command" => "npx my-server" }])
      expect { described_class.call(document: doc) }.to change(McpServer, :count).by(1)
    end

    it "returns action :created" do
      doc    = build_document(mcp_servers: [{ "name" => "my-server", "transport" => "stdio", "command" => "npx my-server" }])
      result = described_class.call(document: doc)
      expect(result.payload[:mcp_servers].first.action).to eq(:created)
    end

    it "stores all provided attributes for stdio transport" do
      doc    = build_document(mcp_servers: [{
        "name"      => "my-stdio-server",
        "transport" => "stdio",
        "command"   => "npx @my/server",
        "env_vars"  => { "API_KEY" => "vault:swarm_export/api_key" }
      }])
      server = described_class.call(document: doc).payload[:mcp_servers].first.record
      expect(server.transport).to eq("stdio")
      expect(server.command).to eq("npx @my/server")
      expect(server.env_vars["API_KEY"]).to eq("vault:swarm_export/api_key")
    end

    it "stores url for sse transport" do
      doc    = build_document(mcp_servers: [{
        "name"      => "my-sse-server",
        "transport" => "sse",
        "url"       => "https://api.example.com/mcp"
      }])
      server = described_class.call(document: doc).payload[:mcp_servers].first.record
      expect(server.transport).to eq("sse")
      expect(server.url).to eq("https://api.example.com/mcp")
    end

    it "stores optional fields when provided" do
      doc    = build_document(mcp_servers: [{
        "name"        => "my-server",
        "transport"   => "stdio",
        "command"     => "npx my-server",
        "npm_package" => "@my/server",
        "icon"        => "🔧",
        "auth_config" => { "token" => "vault:swarm_export/token" }
      }])
      server = described_class.call(document: doc).payload[:mcp_servers].first.record
      expect(server.npm_package).to eq("@my/server")
      expect(server.icon).to eq("🔧")
      expect(server.auth_config["token"]).to eq("vault:swarm_export/token")
    end

    it "defaults enabled to true when not specified" do
      doc    = build_document(mcp_servers: [{ "name" => "my-server", "transport" => "stdio", "command" => "npx my-server" }])
      server = described_class.call(document: doc).payload[:mcp_servers].first.record
      expect(server.enabled).to be true
    end

    it "respects an explicit enabled: false" do
      doc    = build_document(mcp_servers: [{ "name" => "my-server", "transport" => "stdio", "command" => "npx my-server", "enabled" => false }])
      server = described_class.call(document: doc).payload[:mcp_servers].first.record
      expect(server.enabled).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # Conflict — no resolution (default skip)
  # ---------------------------------------------------------------------------

  describe "when a server already exists and no resolution is provided" do
    let!(:existing) { McpServer.create!(name: "my-server", transport: "stdio", command: "npx old-server") }

    it "does not create a new McpServer record" do
      doc = build_document(mcp_servers: [{ "name" => "my-server", "transport" => "stdio", "command" => "npx new-server" }])
      expect { described_class.call(document: doc) }.not_to change(McpServer, :count)
    end

    it "returns action :skipped" do
      doc    = build_document(mcp_servers: [{ "name" => "my-server", "transport" => "stdio", "command" => "npx new-server" }])
      result = described_class.call(document: doc)
      expect(result.payload[:mcp_servers].first.action).to eq(:skipped)
    end

    it "leaves the existing record unchanged" do
      doc = build_document(mcp_servers: [{ "name" => "my-server", "transport" => "stdio", "command" => "npx new-server" }])
      described_class.call(document: doc)
      expect(existing.reload.command).to eq("npx old-server")
    end
  end

  # ---------------------------------------------------------------------------
  # Conflict — :overwrite resolution
  # ---------------------------------------------------------------------------

  describe "resolution :overwrite" do
    let!(:existing) { McpServer.create!(name: "my-server", transport: "stdio", command: "npx old-server") }

    it "updates the existing record and returns :updated" do
      doc    = build_document(mcp_servers: [{ "name" => "my-server", "transport" => "stdio", "command" => "npx new-server" }])
      result = described_class.call(document: doc, resolutions: { "my-server" => :overwrite })
      expect(result.payload[:mcp_servers].first.action).to eq(:updated)
      expect(existing.reload.command).to eq("npx new-server")
    end
  end

  # ---------------------------------------------------------------------------
  # Conflict — :rename resolution
  # ---------------------------------------------------------------------------

  describe "resolution :rename" do
    let!(:existing) { McpServer.create!(name: "my-server", transport: "stdio", command: "npx old-server") }

    it "creates a new McpServer with a suffixed name and returns :renamed" do
      doc    = build_document(mcp_servers: [{ "name" => "my-server", "transport" => "stdio", "command" => "npx new-server" }])
      result = described_class.call(document: doc, resolutions: { "my-server" => :rename })
      dr     = result.payload[:mcp_servers].first
      expect(dr.action).to eq(:renamed)
      expect(dr.name).to eq("my-server-2")
      expect(dr.record.command).to eq("npx new-server")
    end

    it "increments the suffix when -2 is also taken" do
      McpServer.create!(name: "my-server-2", transport: "stdio", command: "npx another")
      doc    = build_document(mcp_servers: [{ "name" => "my-server", "transport" => "stdio", "command" => "npx new-server" }])
      result = described_class.call(document: doc, resolutions: { "my-server" => :rename })
      expect(result.payload[:mcp_servers].first.name).to eq("my-server-3")
    end
  end
end
