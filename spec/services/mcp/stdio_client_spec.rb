# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::StdioClient do
  let(:server) { create(:mcp_server, :stdio, :connected) }

  before do
    allow(Mcp::StdioSession).to receive(:command_for)
      .and_return([ RbConfig.ruby, Rails.root.join("spec/fixtures/mcp/echo_server.rb").to_s ])
  end

  after { Mcp::StdioRegistry.shutdown }

  describe ".discover_tools" do
    it "fetches tools through the handshaken session" do
      result = described_class.discover_tools(server)

      expect(result).to be_success
      expect(result.data[:tools]).to eq([ { "name" => "echo", "description" => "Echo" } ])
      expect(server.reload.status).to eq("connected")
      expect(server.discovered_tools.first["name"]).to eq("echo")
    end

    it "marks the server errored when the process cannot be started" do
      allow(Mcp::StdioSession).to receive(:command_for).and_return([ "/nonexistent/mcp-server" ])

      result = described_class.discover_tools(server)

      expect(result).not_to be_success
      expect(server.reload.status).to eq("error")
    end
  end

  describe ".call_tool" do
    it "returns the tool's text output" do
      result = described_class.call_tool(server, tool_name: "echo", arguments: { text: "hi" })

      expect(result).to be_success
      expect(result.data[:output]).to match(/\Apid=\d+\z/)
    end

    it "reuses one process across calls" do
      first = described_class.call_tool(server, tool_name: "echo")
      second = described_class.call_tool(server, tool_name: "echo")

      expect(second.data[:output]).to eq(first.data[:output])
    end

    it "reports a failed call without raising" do
      result = described_class.call_tool(server, tool_name: "die")

      expect(result).not_to be_success
      expect(result.error).to be_present
    end
  end
end

RSpec.describe Mcp::StdioSession, ".command_for" do
  it "hands the child the real value behind a command reference" do
    VaultEntry.create!(namespace: "mcp_x", key: "arg_api_key", value: "sk-real")
    server = create(:mcp_server, :stdio, command: "npx srv --api-key vault:mcp_x/arg_api_key")

    argv = described_class.command_for(server)

    expect(argv.last(4)).to eq(%w[npx srv --api-key sk-real])
    expect(argv).not_to include("vault:mcp_x/arg_api_key")
  end
end
