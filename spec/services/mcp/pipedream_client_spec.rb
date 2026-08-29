# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::PipedreamClient, type: :service do
  let(:url) { described_class::REMOTE_MCP_URL }
  let(:server) do
    create(:mcp_server, :sse, url: url,
      metadata: { "provider" => "pipedream", "app_slug" => "slack", "external_user_id" => "user-1" })
  end
  let(:tokens) do
    instance_double(Pipedream::TokenManager,
      configured?: true, access_token: "pd-token", project_id: "proj_1", environment: "development")
  end
  let(:client) { described_class.new(server, token_manager: tokens) }

  # Routes the shared MCP endpoint by JSON-RPC method.
  def stub_mcp(tools_list: nil, tools_call: nil, list_status: 200, sse: false)
    stub_request(:post, url).to_return do |req|
      method = JSON.parse(req.body)["method"]
      id = JSON.parse(req.body)["id"]
      case method
      when "initialize"
        { status: 200, headers: { "Content-Type" => "application/json" },
          body: { jsonrpc: "2.0", id: id, result: {} }.to_json }
      when "notifications/initialized"
        { status: 202, body: "" }
      when "tools/list"
        { status: list_status, headers: { "Content-Type" => "application/json" },
          body: { jsonrpc: "2.0", id: id, result: { tools: tools_list || [] } }.to_json }
      when "tools/call"
        if sse
          { status: 200, headers: { "Content-Type" => "text/event-stream" },
            body: "event: message\ndata: #{{ jsonrpc: '2.0', id: id, result: tools_call }.to_json}\n\n" }
        else
          { status: 200, headers: { "Content-Type" => "application/json" },
            body: { jsonrpc: "2.0", id: id, result: tools_call }.to_json }
        end
      end
    end
  end

  describe "#discover_tools" do
    it "lists tools and marks the server connected with the right headers" do
      stub_mcp(tools_list: [ { "name" => "send_message", "description" => "Send a Slack message" } ])

      result = client.discover_tools

      expect(result).to be_success
      expect(result.data[:tools].first["name"]).to eq("send_message")
      expect(server.reload.status).to eq("connected")
      expect(server.discovered_tools.size).to eq(1)
      expect(WebMock).to have_requested(:post, url)
        .with(headers: {
          "Authorization" => "Bearer pd-token",
          "x-pd-project-id" => "proj_1",
          "x-pd-environment" => "development",
          "x-pd-external-user-id" => "user-1",
          "x-pd-app-slug" => "slack"
        }).at_least_once
    end

    it "marks the server errored when not configured" do
      allow(tokens).to receive(:configured?).and_return(false)

      result = client.discover_tools

      expect(result).not_to be_success
      expect(server.reload.status).to eq("error")
    end

    it "marks the server errored on a JSON-RPC error" do
      stub_request(:post, url).to_return do |req|
        body = JSON.parse(req.body)
        if body["method"] == "tools/list"
          { status: 200, headers: { "Content-Type" => "application/json" },
            body: { jsonrpc: "2.0", id: body["id"], error: { message: "boom" } }.to_json }
        else
          { status: 200, headers: { "Content-Type" => "application/json" },
            body: { jsonrpc: "2.0", id: body["id"], result: {} }.to_json }
        end
      end

      result = client.discover_tools

      expect(result).not_to be_success
      expect(result.error).to include("boom")
      expect(server.reload.status).to eq("error")
    end
  end

  describe "#call_tool" do
    it "calls a tool and returns joined text content" do
      stub_mcp(tools_call: { "content" => [ { "type" => "text", "text" => "message sent" } ] })

      result = client.call_tool(tool_name: "send_message", arguments: { "channel" => "#general" })

      expect(result).to be_success
      expect(result.data[:output]).to eq("message sent")
    end

    it "parses an SSE (text/event-stream) response" do
      stub_mcp(tools_call: { "content" => [ { "type" => "text", "text" => "streamed reply" } ] }, sse: true)

      result = client.call_tool(tool_name: "send_message", arguments: {})

      expect(result).to be_success
      expect(result.data[:output]).to eq("streamed reply")
    end

    it "fails cleanly when no access token is available" do
      allow(tokens).to receive(:access_token).and_return(nil)

      result = client.call_tool(tool_name: "send_message", arguments: {})

      expect(result).not_to be_success
    end
  end
end
