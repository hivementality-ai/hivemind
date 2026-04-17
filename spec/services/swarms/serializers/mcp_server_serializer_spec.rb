# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Serializers::McpServerSerializer do
  def build_server(attrs = {})
    McpServer.new({
      name:      "my-server",
      transport: "stdio",
      command:   "npx my-server",
      enabled:   true
    }.merge(attrs))
  end

  describe "#call" do
    it "returns a hash with required fields" do
      server = build_server
      result = described_class.call(mcp_server: server)

      expect(result["name"]).to eq("my-server")
      expect(result["transport"]).to eq("stdio")
    end

    it "includes command for stdio transport" do
      server = build_server(transport: "stdio", command: "npx @my/server")
      result = described_class.call(mcp_server: server)
      expect(result["command"]).to eq("npx @my/server")
    end

    it "includes url for sse transport" do
      server = build_server(transport: "sse", command: nil, url: "https://api.example.com/mcp")
      result = described_class.call(mcp_server: server)
      expect(result["url"]).to eq("https://api.example.com/mcp")
    end

    it "includes npm_package when set" do
      server = build_server(npm_package: "@my/server-package")
      result = described_class.call(mcp_server: server)
      expect(result["npm_package"]).to eq("@my/server-package")
    end

    it "omits npm_package when blank" do
      server = build_server(npm_package: nil)
      result = described_class.call(mcp_server: server)
      expect(result).not_to have_key("npm_package")
    end

    it "includes icon when set" do
      server = build_server(icon: "🔧")
      result = described_class.call(mcp_server: server)
      expect(result["icon"]).to eq("🔧")
    end

    it "includes env_vars when present" do
      server = build_server(env_vars: { "API_KEY" => "vault:swarm_export/api_key" })
      result = described_class.call(mcp_server: server)
      expect(result["env_vars"]["API_KEY"]).to eq("vault:swarm_export/api_key")
    end

    it "omits env_vars when empty" do
      server = build_server(env_vars: {})
      result = described_class.call(mcp_server: server)
      expect(result).not_to have_key("env_vars")
    end

    it "includes auth_config when present" do
      server = build_server(auth_config: { "token" => "vault:swarm_export/token" })
      result = described_class.call(mcp_server: server)
      expect(result["auth_config"]["token"]).to eq("vault:swarm_export/token")
    end

    it "excludes runtime-only fields" do
      server = build_server
      result = described_class.call(mcp_server: server)

      expect(result).not_to have_key("status")
      expect(result).not_to have_key("last_error")
      expect(result).not_to have_key("discovered_tools")
      expect(result).not_to have_key("last_connected_at")
      expect(result).not_to have_key("preset")
    end

    it "includes enabled when set" do
      server = build_server(enabled: false)
      result = described_class.call(mcp_server: server)
      expect(result["enabled"]).to be false
    end
  end
end
