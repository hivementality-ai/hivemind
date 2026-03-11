# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::McpExecutor do
  describe "#call" do
    let(:server) { create(:mcp_server, :stdio, :connected) }

    def build_executor(input)
      described_class.new(input: input)
    end

    it "fails when server_id is missing" do
      result = build_executor({ "tool_name" => "test" }).call
      expect(result).not_to be_success
      expect(result.error).to eq("Missing server_id")
    end

    it "fails when tool_name is missing" do
      result = build_executor({ "server_id" => server.id }).call
      expect(result).not_to be_success
      expect(result.error).to eq("Missing tool_name")
    end

    it "fails when server not found" do
      result = build_executor({ "server_id" => 0, "tool_name" => "test" }).call
      expect(result).not_to be_success
      expect(result.error).to eq("MCP server not found")
    end

    it "fails when server is disconnected" do
      server.update!(status: "disconnected")
      result = build_executor({ "server_id" => server.id, "tool_name" => "test" }).call
      expect(result).not_to be_success
      expect(result.error).to eq("MCP server is not connected")
    end

    it "delegates to StdioClient for stdio servers" do
      expect(Mcp::StdioClient).to receive(:call_tool)
        .with(server, tool_name: "read_file", arguments: { "path" => "/test" })
        .and_return(ServiceResponse.success(data: { output: "content" }))

      result = build_executor({ "server_id" => server.id, "tool_name" => "read_file", "path" => "/test" }).call
      expect(result).to be_success
    end

    it "delegates to SseClient for SSE servers" do
      sse_server = create(:mcp_server, :sse, :connected)
      expect(Mcp::SseClient).to receive(:call_tool)
        .with(sse_server, tool_name: "test", arguments: {})
        .and_return(ServiceResponse.success(data: { output: "ok" }))

      result = build_executor({ "server_id" => sse_server.id, "tool_name" => "test" }).call
      expect(result).to be_success
    end

    it "reads from nested _mcp hash" do
      expect(Mcp::StdioClient).to receive(:call_tool)
        .with(server, tool_name: "read_file", arguments: {})
        .and_return(ServiceResponse.success(data: { output: "ok" }))

      result = build_executor({ "_mcp" => { "server_id" => server.id, "original_tool_name" => "read_file" } }).call
      expect(result).to be_success
    end
  end
end
