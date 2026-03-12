# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpServer, type: :model do
  subject(:server) { build(:mcp_server) }

  describe "associations" do
    it { is_expected.to have_many(:agent_mcp_servers).dependent(:destroy) }
    it { is_expected.to have_many(:agents).through(:agent_mcp_servers) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name) }
    it { is_expected.to validate_presence_of(:transport) }
    it { is_expected.to validate_inclusion_of(:transport).in_array(McpServer::TRANSPORTS) }

    context "when stdio transport" do
      before { server.transport = "stdio" }
      it { is_expected.to validate_presence_of(:command) }
    end

    context "when sse transport" do
      before { server.transport = "sse"; server.command = nil }
      it { is_expected.to validate_presence_of(:url) }
    end
  end

  describe "scopes" do
    it "returns enabled servers" do
      enabled = create(:mcp_server, enabled: true)
      create(:mcp_server, :disabled)
      expect(McpServer.enabled).to eq([ enabled ])
    end

    it "returns preset servers" do
      preset = create(:mcp_server, :preset)
      create(:mcp_server)
      expect(McpServer.preset).to eq([ preset ])
    end

    it "filters by transport" do
      stdio = create(:mcp_server, :stdio)
      create(:mcp_server, :sse)
      expect(McpServer.by_transport("stdio")).to eq([ stdio ])
    end

    it "returns connected servers" do
      connected = create(:mcp_server, :connected)
      create(:mcp_server, :disconnected)
      expect(McpServer.connected).to eq([ connected ])
    end

    it "returns errored servers" do
      errored = create(:mcp_server, :error)
      create(:mcp_server)
      expect(McpServer.errored).to eq([ errored ])
    end
  end

  describe "#stdio?" do
    it "returns true for stdio transport" do
      server.transport = "stdio"
      expect(server.stdio?).to be true
    end

    it "returns false for sse transport" do
      server.transport = "sse"
      expect(server.stdio?).to be false
    end
  end

  describe "#sse?" do
    it "returns true for sse transport" do
      server.transport = "sse"
      expect(server.sse?).to be true
    end
  end

  describe "#connected?" do
    it "returns true when status is connected" do
      server.status = "connected"
      expect(server.connected?).to be true
    end

    it "returns false when status is disconnected" do
      server.status = "disconnected"
      expect(server.connected?).to be false
    end
  end

  describe "#mark_connected!" do
    it "updates status and timestamps" do
      server = create(:mcp_server)
      server.mark_connected!
      expect(server.reload.status).to eq("connected")
      expect(server.last_connected_at).to be_present
      expect(server.last_error).to be_nil
    end

    it "stores pid and tools when provided" do
      server = create(:mcp_server)
      tools = [ { "name" => "test" } ]
      server.mark_connected!(pid: "12345", tools: tools)
      expect(server.reload.metadata["pid"]).to eq("12345")
      expect(server.discovered_tools).to eq(tools)
      expect(server.tools_refreshed_at).to be_present
    end
  end

  describe "#mark_error!" do
    it "updates status and error message" do
      server = create(:mcp_server)
      server.mark_error!("Connection refused")
      expect(server.reload.status).to eq("error")
      expect(server.last_error).to eq("Connection refused")
    end
  end

  describe "#mark_disconnected!" do
    it "updates status to disconnected" do
      server = create(:mcp_server, :connected)
      server.mark_disconnected!
      expect(server.reload.status).to eq("disconnected")
    end
  end

  describe "#update_discovered_tools!" do
    it "stores tools and refreshed timestamp" do
      server = create(:mcp_server)
      tools = [ { "name" => "test", "description" => "A test tool" } ]
      server.update_discovered_tools!(tools)
      expect(server.reload.discovered_tools).to eq(tools)
      expect(server.tools_refreshed_at).to be_present
    end
  end

  describe "#resolved_env_vars" do
    it "returns empty hash when no env vars" do
      expect(server.resolved_env_vars).to eq({})
    end

    it "returns plain values as-is" do
      server.env_vars = { "KEY" => "plain-value" }
      expect(server.resolved_env_vars).to eq({ "KEY" => "plain-value" })
    end

    it "resolves vault references" do
      create(:vault_entry, namespace: "mcp", key: "secret", value: "resolved-secret")
      server.env_vars = { "SECRET" => "vault:mcp/secret" }
      expect(server.resolved_env_vars).to eq({ "SECRET" => "resolved-secret" })
    end

    it "returns vault reference when entry not found" do
      server.env_vars = { "SECRET" => "vault:mcp/missing" }
      expect(server.resolved_env_vars).to eq({ "SECRET" => "vault:mcp/missing" })
    end
  end

  describe "#resolved_auth_headers" do
    it "returns empty hash when no auth config" do
      expect(server.resolved_auth_headers).to eq({})
    end

    it "resolves vault references in auth config" do
      create(:vault_entry, namespace: "mcp", key: "token", value: "bearer-token")
      server.auth_config = { "Authorization" => "vault:mcp/token" }
      expect(server.resolved_auth_headers).to eq({ "Authorization" => "bearer-token" })
    end
  end
end
