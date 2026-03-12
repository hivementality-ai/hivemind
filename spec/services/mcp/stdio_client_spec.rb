# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::StdioClient do
  let(:server) { create(:mcp_server, :stdio, :connected) }

  describe ".discover_tools" do
    it "fetches tools via JSON-RPC" do
      tools = [ { "name" => "read_file", "description" => "Read a file" } ]
      rpc_response = { "jsonrpc" => "2.0", "id" => "uuid", "result" => { "tools" => tools } }.to_json
      allow(Open3).to receive(:capture3).and_return([ rpc_response, "", instance_double(Process::Status, success?: true) ])

      result = described_class.discover_tools(server)
      expect(result).to be_success
      expect(result.data[:tools]).to eq(tools)
      expect(server.reload.status).to eq("connected")
    end

    it "handles command failure" do
      allow(Open3).to receive(:capture3).and_return([ "", "error", instance_double(Process::Status, success?: false) ])

      result = described_class.discover_tools(server)
      expect(result).not_to be_success
      expect(server.reload.status).to eq("error")
    end

    it "handles invalid JSON response" do
      allow(Open3).to receive(:capture3).and_return([ "not json\n", "", instance_double(Process::Status, success?: true) ])

      result = described_class.discover_tools(server)
      expect(result).not_to be_success
    end
  end

  describe ".call_tool" do
    it "calls tool via JSON-RPC" do
      content = [ { "type" => "text", "text" => "file contents" } ]
      rpc_response = { "jsonrpc" => "2.0", "id" => "uuid", "result" => { "content" => content } }.to_json
      allow(Open3).to receive(:capture3).and_return([ rpc_response, "", instance_double(Process::Status, success?: true) ])

      result = described_class.call_tool(server, tool_name: "read_file", arguments: { path: "/test" })
      expect(result).to be_success
      expect(result.data[:output]).to include("file contents")
    end

    it "handles RPC error" do
      rpc_response = { "jsonrpc" => "2.0", "id" => "uuid", "error" => { "message" => "not found" } }.to_json
      allow(Open3).to receive(:capture3).and_return([ rpc_response, "", instance_double(Process::Status, success?: true) ])

      result = described_class.call_tool(server, tool_name: "missing", arguments: {})
      expect(result).not_to be_success
    end

    it "passes env vars to docker exec" do
      server.update!(env_vars: { "API_KEY" => "test-key" })
      rpc_response = { "jsonrpc" => "2.0", "id" => "uuid", "result" => { "content" => [ { "text" => "ok" } ] } }.to_json
      allow(Open3).to receive(:capture3).and_return([ rpc_response, "", instance_double(Process::Status, success?: true) ])

      described_class.call_tool(server, tool_name: "test", arguments: {})
      expect(Open3).to have_received(:capture3) do |*args|
        expect(args).to include("--env")
      end
    end
  end
end
