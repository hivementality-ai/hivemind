# frozen_string_literal: true

require "rails_helper"

RSpec.describe Providers::Anthropic::SdkProxyClient, type: :service do
  subject(:proxy_client) { described_class.new(api_key: "sk-ant-oat-test-key", base_url: "http://sdk-proxy:3003") }

  let(:base_params) do
    {
      model: "claude-sonnet-4-5",
      messages: [ { role: "user", content: "Hello" } ],
      max_tokens: 8192,
      system: [ { type: "text", text: "You are helpful", cache_control: { type: "ephemeral" } } ]
    }
  end

  describe "#chat" do
    context "sync (no block)" do
      it "returns content on success" do
        stub_request(:post, "http://sdk-proxy:3003/v1/chat")
          .with(
            headers: { "Authorization" => "Bearer sk-ant-oat-test-key", "Content-Type" => "application/json" },
            body: hash_including(stream: false, model: "claude-sonnet-4-5")
          )
          .to_return(
            status: 200,
            body: { content: "Hello there!", thinking: nil, tool_calls: nil, usage: { input_tokens: 10, output_tokens: 5 } }.to_json
          )

        result = proxy_client.chat(params: base_params)

        expect(result).to be_success
        expect(result.data[:content]).to eq("Hello there!")
        expect(result.data[:usage]).to eq(input_tokens: 10, output_tokens: 5)
      end

      it "returns tool calls" do
        stub_request(:post, "http://sdk-proxy:3003/v1/chat")
          .to_return(
            status: 200,
            body: {
              content: nil,
              tool_calls: [ { id: "tc_1", name: "shell", input: { command: "ls" } } ],
              usage: {}
            }.to_json
          )

        result = proxy_client.chat(params: base_params)

        expect(result).to be_success
        expect(result.data[:tool_calls]).to eq([
          { "id" => "tc_1", "name" => "shell", "input" => { "command" => "ls" } }
        ])
      end

      it "returns failure on HTTP error" do
        stub_request(:post, "http://sdk-proxy:3003/v1/chat")
          .to_return(status: 500, body: "Internal Server Error")

        result = proxy_client.chat(params: base_params)

        expect(result).not_to be_success
        expect(result.error).to include("SDK proxy error (500)")
      end

      it "passes MCP context options through" do
        stub_request(:post, "http://sdk-proxy:3003/v1/chat")
          .with(body: hash_including(agent_id: "agent-1", session_id: "sess-1"))
          .to_return(status: 200, body: { content: "ok", usage: {} }.to_json)

        result = proxy_client.chat(params: base_params, options: { agent_id: "agent-1", session_id: "sess-1" })

        expect(result).to be_success
      end
    end

    context "streaming (block given)" do
      it "yields content chunks and returns accumulated content" do
        sse_body = [
          "event: content\ndata: #{({ content: 'Hello ' }).to_json}\n\n",
          "event: content\ndata: #{({ content: 'world!' }).to_json}\n\n",
          "event: result\ndata: #{({ usage: { input_tokens: 10, output_tokens: 5 } }).to_json}\n\n",
          "event: done\ndata: {}\n\n"
        ].join

        stub_request(:post, "http://sdk-proxy:3003/v1/chat")
          .with(body: hash_including(stream: true))
          .to_return(status: 200, body: sse_body)

        chunks = []
        result = proxy_client.chat(params: base_params) { |chunk| chunks << chunk }

        expect(result).to be_success
        expect(result.data[:content]).to eq("Hello world!")
        expect(chunks).to include(
          { type: "content", content: "Hello " },
          { type: "content", content: "world!" }
        )
      end

      it "yields thinking chunks" do
        sse_body = [
          "event: thinking\ndata: #{({ thinking: 'Hmm...' }).to_json}\n\n",
          "event: content\ndata: #{({ content: 'Answer' }).to_json}\n\n",
          "event: done\ndata: {}\n\n"
        ].join

        stub_request(:post, "http://sdk-proxy:3003/v1/chat")
          .to_return(status: 200, body: sse_body)

        chunks = []
        result = proxy_client.chat(params: base_params) { |chunk| chunks << chunk }

        expect(result).to be_success
        expect(result.data[:thinking]).to eq("Hmm...")
        expect(result.data[:content]).to eq("Answer")
      end

      it "yields tool_start and tool_result events" do
        sse_body = [
          "event: tool_start\ndata: #{({ tool: 'shell', input: { command: 'ls' } }).to_json}\n\n",
          "event: tool_result\ndata: #{({ tool: 'shell', output: 'file.txt', success: true }).to_json}\n\n",
          "event: done\ndata: {}\n\n"
        ].join

        stub_request(:post, "http://sdk-proxy:3003/v1/chat")
          .to_return(status: 200, body: sse_body)

        chunks = []
        proxy_client.chat(params: base_params) { |chunk| chunks << chunk }

        expect(chunks).to include(
          { type: "tool_start", tool: "shell", input: { "command" => "ls" } },
          { type: "tool_result", tool: "shell", output: "file.txt", success: true }
        )
      end

      it "returns nil thinking when no thinking content" do
        sse_body = "event: content\ndata: #{({ content: 'Just text' }).to_json}\n\nevent: done\ndata: {}\n\n"

        stub_request(:post, "http://sdk-proxy:3003/v1/chat")
          .to_return(status: 200, body: sse_body)

        result = proxy_client.chat(params: base_params) { |_| }

        expect(result.data[:thinking]).to be_nil
      end
    end
  end

  describe "parse_sse_frame (via streaming)" do
    it "handles malformed JSON gracefully" do
      sse_body = "event: content\ndata: {invalid json}\n\nevent: content\ndata: #{({ content: 'ok' }).to_json}\n\nevent: done\ndata: {}\n\n"

      stub_request(:post, "http://sdk-proxy:3003/v1/chat")
        .to_return(status: 200, body: sse_body)

      chunks = []
      result = proxy_client.chat(params: base_params) { |chunk| chunks << chunk }

      expect(result).to be_success
      expect(result.data[:content]).to eq("ok")
      expect(chunks.size).to eq(1)
    end

    it "skips frames without event type" do
      sse_body = "data: #{({ content: 'orphan' }).to_json}\n\nevent: content\ndata: #{({ content: 'ok' }).to_json}\n\nevent: done\ndata: {}\n\n"

      stub_request(:post, "http://sdk-proxy:3003/v1/chat")
        .to_return(status: 200, body: sse_body)

      chunks = []
      proxy_client.chat(params: base_params) { |chunk| chunks << chunk }

      expect(chunks).to eq([ { type: "content", content: "ok" } ])
    end
  end
end
