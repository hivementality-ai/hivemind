# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::ToolResolver do
  let(:agent) { create(:agent) }

  describe ".call" do
    it "returns empty tools when agent has no MCP servers" do
      result = described_class.call(agent)
      expect(result).to be_success
      expect(result.data[:tools]).to eq([])
    end

    it "skips disconnected servers" do
      server = create(:mcp_server, :disconnected, :with_tools)
      create(:agent_mcp_server, agent: agent, mcp_server: server)
      result = described_class.call(agent)
      expect(result.data[:tools]).to eq([])
    end

    it "skips disabled servers" do
      server = create(:mcp_server, :disabled, :connected, :with_tools)
      create(:agent_mcp_server, agent: agent, mcp_server: server)
      result = described_class.call(agent)
      expect(result.data[:tools]).to eq([])
    end

    it "resolves tools from connected enabled servers" do
      server = create(:mcp_server, :connected, :with_tools, name: "TestServer")
      create(:agent_mcp_server, agent: agent, mcp_server: server)

      result = described_class.call(agent)
      tools = result.data[:tools]
      expect(tools.length).to eq(2)
      expect(tools.first[:name]).to start_with("mcp_testserver_")
      expect(tools.first[:_mcp][:server_id]).to eq(server.id)
      expect(tools.first[:_mcp][:original_tool_name]).to eq("read_file")
    end

    it "resolves tools from multiple servers" do
      server1 = create(:mcp_server, :connected, :with_tools, name: "Server One")
      server2 = create(:mcp_server, :connected, :with_tools, name: "Server Two")
      create(:agent_mcp_server, agent: agent, mcp_server: server1)
      create(:agent_mcp_server, agent: agent, mcp_server: server2)

      result = described_class.call(agent)
      expect(result.data[:tools].length).to eq(4)
    end

    it "includes input schema" do
      server = create(:mcp_server, :connected, :with_tools, name: "Schema Test")
      create(:agent_mcp_server, agent: agent, mcp_server: server)

      result = described_class.call(agent)
      expect(result.data[:tools].first[:input_schema]).to be_a(Hash)
    end
  end
end
