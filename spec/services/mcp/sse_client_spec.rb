# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::SseClient do
  let(:server) { create(:mcp_server, :sse, :connected, url: "https://mcp.example.com") }

  describe ".discover_tools" do
    it "fetches and stores tools" do
      tools = [{ "name" => "test_tool", "description" => "A test" }]
      stub_request(:get, "https://mcp.example.com/tools")
        .to_return(status: 200, body: { tools: tools }.to_json, headers: { "Content-Type" => "application/json" })

      result = described_class.discover_tools(server)
      expect(result).to be_success
      expect(result.data[:tools]).to eq(tools)
      expect(server.reload.status).to eq("connected")
    end

    it "handles errors" do
      stub_request(:get, "https://mcp.example.com/tools")
        .to_return(status: 500, body: "Internal Server Error")

      result = described_class.discover_tools(server)
      expect(result).not_to be_success
      expect(server.reload.status).to eq("error")
    end

    it "handles connection failures" do
      stub_request(:get, "https://mcp.example.com/tools")
        .to_raise(Errno::ECONNREFUSED)

      result = described_class.discover_tools(server)
      expect(result).not_to be_success
    end
  end

  describe ".call_tool" do
    it "calls tool and returns result" do
      content = [{ "type" => "text", "text" => "Hello" }]
      stub_request(:post, "https://mcp.example.com/tools/call")
        .to_return(status: 200, body: { content: content }.to_json, headers: { "Content-Type" => "application/json" })

      result = described_class.call_tool(server, tool_name: "greet", arguments: { name: "World" })
      expect(result).to be_success
      expect(result.data[:output]).to include("Hello")
    end

    it "handles errors" do
      stub_request(:post, "https://mcp.example.com/tools/call")
        .to_return(status: 500, body: "error")

      result = described_class.call_tool(server, tool_name: "greet", arguments: {})
      expect(result).not_to be_success
    end

    it "includes auth headers" do
      server.update!(auth_config: { "Authorization" => "Bearer test-token" })
      stub_request(:post, "https://mcp.example.com/tools/call")
        .with(headers: { "Authorization" => "Bearer test-token" })
        .to_return(status: 200, body: { content: [{ "text" => "ok" }] }.to_json)

      result = described_class.call_tool(server, tool_name: "test", arguments: {})
      expect(result).to be_success
    end
  end
end
