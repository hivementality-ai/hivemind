# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::HttpClient do
  let(:url) { "https://mcp.example.com/mcp" }
  let(:server) { create(:mcp_server, :sse, :connected, url: url) }
  let(:json_headers) { { "Content-Type" => "application/json" } }
  let(:sse_headers) { { "Content-Type" => "text/event-stream" } }

  def rpc_body(request)
    JSON.parse(request.body)
  end

  def stub_rpc(method, result: nil, error: nil, headers: json_headers)
    stub_request(:post, url).with { |req| rpc_body(req)["method"] == method }.to_return do |req|
      message = { jsonrpc: "2.0", id: rpc_body(req)["id"] }
      error ? message[:error] = error : message[:result] = result
      { status: 200, headers: headers, body: message.to_json }
    end
  end

  def stub_initialize(headers: {})
    stub_rpc("initialize", result: { protocolVersion: "2025-03-26", capabilities: {} }, headers: json_headers.merge(headers))
    stub_request(:post, url).with { |req| rpc_body(req)["method"] == "notifications/initialized" }
      .to_return(status: 202, body: "")
  end

  describe ".discover_tools" do
    it "initializes, announces readiness, then lists and stores tools" do
      tools = [ { "name" => "test_tool", "description" => "A test" } ]
      stub_initialize
      stub_rpc("tools/list", result: { tools: tools })

      result = described_class.discover_tools(server)

      expect(result).to be_success
      expect(result.data[:tools]).to eq(tools)
      expect(server.reload.discovered_tools).to eq(tools)
      expect(a_request(:post, url).with { |r| rpc_body(r)["method"] == "notifications/initialized" }).to have_been_made.once
    end

    it "sends the streamable HTTP accept header" do
      stub_initialize
      stub_rpc("tools/list", result: { tools: [] })

      described_class.discover_tools(server)

      expect(a_request(:post, url).with(headers: { "Accept" => "application/json, text/event-stream" })).to have_been_made.times(3)
    end

    it "reuses the session id the server issues on every later request" do
      stub_initialize(headers: { "Mcp-Session-Id" => "sess-42" })
      stub_rpc("tools/list", result: { tools: [] })

      described_class.discover_tools(server)

      expect(a_request(:post, url).with { |r| rpc_body(r)["method"] == "initialize" && r.headers["Mcp-Session-Id"].nil? }).to have_been_made.once
      expect(a_request(:post, url).with(headers: { "Mcp-Session-Id" => "sess-42" })).to have_been_made.twice
    end

    it "follows tools/list pagination" do
      stub_initialize
      stub_request(:post, url).with { |r| rpc_body(r)["method"] == "tools/list" }.to_return do |req|
        body = rpc_body(req)
        result = body.dig("params", "cursor") ? { tools: [ { "name" => "b" } ] } : { tools: [ { "name" => "a" } ], nextCursor: "c2" }
        { status: 200, headers: json_headers, body: { jsonrpc: "2.0", id: body["id"], result: result }.to_json }
      end

      result = described_class.discover_tools(server)

      expect(result.data[:tools].map { |t| t["name"] }).to eq(%w[a b])
    end

    it "marks the server errored on HTTP failure" do
      stub_request(:post, url).to_return(status: 500, body: "Internal Server Error")

      result = described_class.discover_tools(server)

      expect(result).not_to be_success
      expect(server.reload.status).to eq("error")
    end

    it "handles connection failures" do
      stub_request(:post, url).to_raise(Faraday::ConnectionFailed)

      expect(described_class.discover_tools(server)).not_to be_success
    end

    it "turns a JSON-RPC error into a failure" do
      stub_initialize
      stub_rpc("tools/list", error: { code: -32_601, message: "Method not found" })

      result = described_class.discover_tools(server)

      expect(result).not_to be_success
      expect(result.error).to include("Method not found")
    end
  end

  describe ".call_tool" do
    before { stub_initialize(headers: { "Mcp-Session-Id" => "sess-1" }) }

    it "returns the text content of a plain JSON response" do
      stub_rpc("tools/call", result: { content: [ { type: "text", text: "Hello" } ] })

      result = described_class.call_tool(server, tool_name: "greet", arguments: { name: "World" })

      expect(result).to be_success
      expect(result.data[:output]).to eq("Hello")
      expect(a_request(:post, url).with { |r| b = rpc_body(r); b["method"] == "tools/call" && b["params"] == { "name" => "greet", "arguments" => { "name" => "World" } } }).to have_been_made
    end

    it "reads the response out of an SSE body" do
      stub_request(:post, url).with { |r| rpc_body(r)["method"] == "tools/call" }.to_return do |req|
        id = rpc_body(req)["id"]
        note = { jsonrpc: "2.0", method: "notifications/progress", params: {} }
        reply = { jsonrpc: "2.0", id: id, result: { content: [ { type: "text", text: "from stream" } ] } }
        { status: 200, headers: sse_headers, body: "data: #{note.to_json}\n\nevent: message\ndata: #{reply.to_json}\n\n" }
      end

      result = described_class.call_tool(server, tool_name: "greet")

      expect(result).to be_success
      expect(result.data[:output]).to eq("from stream")
    end

    it "turns a JSON-RPC error into a failure" do
      stub_rpc("tools/call", error: { code: -32_602, message: "Invalid params" })

      result = described_class.call_tool(server, tool_name: "greet")

      expect(result).not_to be_success
      expect(result.error).to include("Invalid params")
    end

    it "turns an isError tool result into a failure" do
      stub_rpc("tools/call", result: { isError: true, content: [ { type: "text", text: "disk full" } ] })

      result = described_class.call_tool(server, tool_name: "greet")

      expect(result).not_to be_success
      expect(result.error).to include("disk full")
    end

    it "includes auth headers" do
      server.update!(auth_config: { "Authorization" => "Bearer test-token" })
      stub_rpc("tools/call", result: { content: [ { text: "ok" } ] })

      expect(described_class.call_tool(server, tool_name: "test")).to be_success
      expect(a_request(:post, url).with(headers: { "Authorization" => "Bearer test-token" })).to have_been_made.at_least_once
    end

    it "fails on HTTP errors" do
      stub_request(:post, url).with { |r| rpc_body(r)["method"] == "tools/call" }.to_return(status: 500, body: "error")

      expect(described_class.call_tool(server, tool_name: "greet")).not_to be_success
    end

  describe "OAuth bearer tokens" do
    def connect_oauth!(expires_in: 3600)
      VaultEntry.create!(namespace: "mcp_oauth_#{server.id}", key: "client",
                         value: { client_id: "c1", token_endpoint: "https://auth.example.com/token" }.to_json)
      VaultEntry.create!(namespace: "mcp_oauth_#{server.id}", key: "tokens",
                         value: { access_token: "old", refresh_token: "rt", expires_at: Time.current.to_i + expires_in }.to_json)
    end

    it "sends the stored access token" do
      connect_oauth!
      stub_rpc("tools/call", result: { content: [ { text: "ok" } ] })
      stub_initialize

      expect(described_class.call_tool(server, tool_name: "t")).to be_success
      expect(a_request(:post, url).with(headers: { "Authorization" => "Bearer old" })).to have_been_made.at_least_once
    end

    it "refreshes once on a 401 and retries the request" do
      connect_oauth!
      refresh = stub_request(:post, "https://auth.example.com/token")
        .to_return(status: 200, body: { access_token: "new", expires_in: 3600 }.to_json)
      stub_request(:post, url).with(headers: { "Authorization" => "Bearer old" }).to_return(status: 401, body: "no")
      stub_request(:post, url).with(headers: { "Authorization" => "Bearer new" }).to_return do |req|
        message = rpc_body(req)
        { status: message["id"] ? 200 : 202, headers: json_headers,
          body: message["id"] ? { jsonrpc: "2.0", id: message["id"], result: { protocolVersion: "2025-03-26", content: [ { text: "ok" } ] } }.to_json : "" }
      end

      expect(described_class.call_tool(server, tool_name: "t")).to be_success
      expect(refresh).to have_been_requested.once
    end

    it "gives up after one refresh when the retry is still unauthorized" do
      connect_oauth!
      refresh = stub_request(:post, "https://auth.example.com/token")
        .to_return(status: 200, body: { access_token: "new", expires_in: 3600 }.to_json)
      stub_request(:post, url).to_return(status: 401, body: "no")

      result = described_class.call_tool(server, tool_name: "t")

      expect(result).not_to be_success
      expect(result.error).to include("HTTP 401")
      expect(refresh).to have_been_requested.once
    end

    it "does not try to refresh a server without OAuth tokens" do
      stub_request(:post, url).to_return(status: 401, body: "no")

      expect(described_class.call_tool(server, tool_name: "t")).not_to be_success
      expect(a_request(:post, url)).to have_been_made.times(1)
    end
  end
  end
end
