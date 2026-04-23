# frozen_string_literal: true

require "rails_helper"

RSpec.describe Providers::Anthropic::FaradayClient, type: :service do
  let(:oauth_key) { "sk-ant-oat01-test" }
  let(:api_key) { "sk-ant-api01-test" }

  let(:base_params) do
    {
      model: "claude-sonnet-4-5",
      messages: [ { role: "user", content: "Hello" } ],
      max_tokens: 8192,
      system: "You are helpful"
    }
  end

  describe "#chat (sync)" do
    context "with an API-key token" do
      subject(:client) { described_class.new(api_key: api_key) }

      it "sends x-api-key and no OAuth gate" do
        captured_body = nil
        stub_request(:post, described_class::API_URL)
          .with { |req|
            captured_body = JSON.parse(req.body)
            req.headers["X-Api-Key"] == api_key &&
              req.headers["Anthropic-Beta"].nil?
          }
          .to_return(
            status: 200,
            body: {
              id: "msg_1",
              content: [ { type: "text", text: "Hi" } ],
              usage: { input_tokens: 10, output_tokens: 3 }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        result = client.chat(params: base_params)

        expect(result).to be_success
        expect(result.data[:content]).to eq("Hi")
        expect(result.data[:usage][:input_tokens]).to eq(10)
        expect(captured_body["system"]).to eq([
          { "type" => "text", "text" => "You are helpful", "cache_control" => { "type" => "ephemeral", "ttl" => "1h" } }
        ])
      end

      it "extracts tool_calls from tool_use content blocks" do
        stub_request(:post, described_class::API_URL)
          .to_return(
            status: 200,
            body: {
              content: [
                { type: "tool_use", id: "tu_1", name: "read_file", input: { path: "README.md" } }
              ],
              usage: { input_tokens: 5, output_tokens: 2 }
            }.to_json
          )

        result = client.chat(params: base_params)

        expect(result).to be_success
        expect(result.data[:tool_calls]).to eq([
          { "id" => "tu_1", "name" => "read_file", "input" => { "path" => "README.md" } }
        ])
      end

      it "captures prompt-cache usage fields" do
        stub_request(:post, described_class::API_URL)
          .to_return(
            status: 200,
            body: {
              content: [ { type: "text", text: "ok" } ],
              usage: {
                input_tokens: 100,
                output_tokens: 10,
                cache_creation_input_tokens: 50,
                cache_read_input_tokens: 40
              }
            }.to_json
          )

        result = described_class.new(api_key: api_key).chat(params: base_params)

        expect(result.data[:usage]).to include(
          input_tokens: 100,
          cache_creation_input_tokens: 50,
          cache_read_input_tokens: 40
        )
      end

      it "returns failure on 4xx/5xx with parsed error message" do
        stub_request(:post, described_class::API_URL)
          .to_return(status: 500, body: { error: { message: "Server error" } }.to_json)

        result = described_class.new(api_key: api_key).chat(params: base_params)

        expect(result).not_to be_success
        expect(result.error).to include("500")
        expect(result.error).to include("Server error")
      end
    end

    context "with an OAuth token" do
      subject(:client) { described_class.new(api_key: oauth_key) }

      it "sends Authorization bearer + anthropic-beta + Claude Code headers" do
        stub = stub_request(:post, described_class::API_URL)
          .with(headers: {
            "Authorization" => "Bearer #{oauth_key}",
            "Anthropic-Beta" => "claude-code-20250219,oauth-2025-04-20",
            "User-Agent" => described_class::OAUTH_USER_AGENT,
            "X-App" => "cli"
          })
          .to_return(
            status: 200,
            body: { content: [ { type: "text", text: "Hi" } ], usage: {} }.to_json
          )

        client.chat(params: base_params)

        expect(stub).to have_been_requested
      end

      it "prepends OAUTH_GATE as the first system block with its own cache marker" do
        captured_body = nil
        stub_request(:post, described_class::API_URL)
          .with { |req|
            captured_body = JSON.parse(req.body)
            true
          }
          .to_return(status: 200, body: { content: [], usage: {} }.to_json)

        client.chat(params: base_params)

        expect(captured_body["system"].first).to eq(
          "type" => "text",
          "text" => described_class::OAUTH_GATE,
          "cache_control" => { "type" => "ephemeral", "ttl" => "1h" }
        )
        expect(captured_body["system"][1]["text"]).to eq("You are helpful")
        expect(captured_body["system"][1]["cache_control"]).to eq("type" => "ephemeral", "ttl" => "1h")
      end

      it "emits exactly 2 system markers with OAuth regardless of caller block count" do
        captured_body = nil
        multi_system_params = base_params.merge(
          system: [
            { type: "text", text: "Block A" },
            { type: "text", text: "Block B" },
            { type: "text", text: "Block C" }
          ]
        )
        stub_request(:post, described_class::API_URL)
          .with { |req| captured_body = JSON.parse(req.body); true }
          .to_return(status: 200, body: { content: [], usage: {} }.to_json)

        client.chat(params: multi_system_params)

        # OAUTH_GATE + 3 caller blocks = 4 system blocks; markers only on
        # OAUTH_GATE (tier-1) and the last caller block (tier-2).
        system_markers = captured_body["system"].count { |b| b["cache_control"] }
        expect(system_markers).to eq(2)
        expect(captured_body["system"].first["cache_control"]).to eq("type" => "ephemeral", "ttl" => "1h")
        expect(captured_body["system"].last["cache_control"]).to eq("type" => "ephemeral", "ttl" => "1h")
        expect(captured_body["system"][1]).not_to have_key("cache_control")
        expect(captured_body["system"][2]).not_to have_key("cache_control")
      end

      it "stays within Anthropic's 4-cache-control-marker limit end-to-end" do
        captured_body = nil
        big_params = base_params.merge(
          system: [
            { type: "text", text: "Block A" },
            { type: "text", text: "Block B" },
            { type: "text", text: "Block C" }
          ],
          tools: [
            { name: "a", description: "a", input_schema: { type: "object" } },
            { name: "b", description: "b", input_schema: { type: "object" } }
          ]
        )
        stub_request(:post, described_class::API_URL)
          .with { |req| captured_body = JSON.parse(req.body); true }
          .to_return(status: 200, body: { content: [], usage: {} }.to_json)

        client.chat(params: big_params)

        total_markers = 0
        total_markers += Array(captured_body["system"]).count { |b| b["cache_control"] }
        total_markers += Array(captured_body["tools"]).count { |t| t["cache_control"] }
        Array(captured_body["messages"]).each do |m|
          total_markers += Array(m["content"]).count { |c| c.is_a?(Hash) && c["cache_control"] }
        end

        # OAuth + system + tools + last-message should use all 4 markers
        # (leaving nothing on the table) without exceeding Anthropic's cap.
        expect(total_markers).to eq(4)
      end
    end

    context "cache breakpoints" do
      subject(:client) { described_class.new(api_key: api_key) }

      it "marks the last tool with cache_control" do
        captured_body = nil
        stub_request(:post, described_class::API_URL)
          .with { |req| captured_body = JSON.parse(req.body); true }
          .to_return(status: 200, body: { content: [], usage: {} }.to_json)

        client.chat(params: base_params.merge(
          tools: [
            { name: "a", description: "", input_schema: {} },
            { name: "b", description: "", input_schema: {} }
          ]
        ))

        expect(captured_body["tools"].first).not_to have_key("cache_control")
        expect(captured_body["tools"].last["cache_control"]).to eq("type" => "ephemeral", "ttl" => "1h")
      end

      it "tags the last message's content with cache_control" do
        captured_body = nil
        stub_request(:post, described_class::API_URL)
          .with { |req| captured_body = JSON.parse(req.body); true }
          .to_return(status: 200, body: { content: [], usage: {} }.to_json)

        client.chat(params: base_params.merge(
          messages: [
            { role: "user", content: "first" },
            { role: "assistant", content: "mid" },
            { role: "user", content: "last" }
          ]
        ))

        last_msg_content = captured_body["messages"].last["content"]
        expect(last_msg_content).to be_an(Array)
        expect(last_msg_content.last["cache_control"]).to eq("type" => "ephemeral", "ttl" => "1h")
        expect(last_msg_content.last["text"]).to eq("last")
      end

      it "preserves array content when tagging the last message" do
        captured_body = nil
        stub_request(:post, described_class::API_URL)
          .with { |req| captured_body = JSON.parse(req.body); true }
          .to_return(status: 200, body: { content: [], usage: {} }.to_json)

        client.chat(params: base_params.merge(
          messages: [
            { role: "user", content: [
              { type: "tool_result", tool_use_id: "tu_1", content: "output" }
            ] }
          ]
        ))

        last_msg_content = captured_body["messages"].last["content"]
        expect(last_msg_content.size).to eq(1)
        expect(last_msg_content.last["cache_control"]).to eq("type" => "ephemeral", "ttl" => "1h")
      end
    end
  end

  describe "#chat (streaming)" do
    subject(:client) { described_class.new(api_key: api_key) }

    it "yields content chunks and accumulates text" do
      sse_body = [
        "event: message_start\ndata: #{({ message: { id: "msg_1", usage: { input_tokens: 5, output_tokens: 0 } } }).to_json}\n\n",
        "event: content_block_start\ndata: #{({ index: 0, content_block: { type: "text", text: "" } }).to_json}\n\n",
        "event: content_block_delta\ndata: #{({ index: 0, delta: { type: "text_delta", text: "Hello " } }).to_json}\n\n",
        "event: content_block_delta\ndata: #{({ index: 0, delta: { type: "text_delta", text: "world" } }).to_json}\n\n",
        "event: content_block_stop\ndata: #{({ index: 0 }).to_json}\n\n",
        "event: message_delta\ndata: #{({ delta: { stop_reason: "end_turn" }, usage: { output_tokens: 3 } }).to_json}\n\n"
      ].join

      stub_request(:post, described_class::API_URL)
        .to_return(status: 200, body: sse_body)

      chunks = []
      result = client.chat(params: base_params) { |c| chunks << c }

      expect(result).to be_success
      expect(result.data[:content]).to eq("Hello world")
      expect(chunks).to include(
        { type: "content", content: "Hello " },
        { type: "content", content: "world" }
      )
    end

    it "accumulates tool_use input across input_json_delta chunks" do
      start_data = { index: 0, content_block: { type: "tool_use", id: "tu_1", name: "shell", input: {} } }.to_json
      delta_a = { index: 0, delta: { type: "input_json_delta", partial_json: '{"cmd' } }.to_json
      delta_b = { index: 0, delta: { type: "input_json_delta", partial_json: '":"ls"}' } }.to_json
      stop_data = { index: 0 }.to_json

      sse_body = [
        "event: content_block_start\ndata: #{start_data}\n\n",
        "event: content_block_delta\ndata: #{delta_a}\n\n",
        "event: content_block_delta\ndata: #{delta_b}\n\n",
        "event: content_block_stop\ndata: #{stop_data}\n\n"
      ].join

      stub_request(:post, described_class::API_URL)
        .to_return(status: 200, body: sse_body)

      result = client.chat(params: base_params) { |_| }

      expect(result.data[:tool_calls]).to eq([
        { "id" => "tu_1", "name" => "shell", "input" => { "cmd" => "ls" } }
      ])
    end

    it "yields thinking_start / thinking / thinking_stop" do
      sse_body = [
        "event: content_block_start\ndata: #{({ index: 0, content_block: { type: "thinking", thinking: "" } }).to_json}\n\n",
        "event: content_block_delta\ndata: #{({ index: 0, delta: { type: "thinking_delta", thinking: "hmm" } }).to_json}\n\n",
        "event: content_block_stop\ndata: #{({ index: 0 }).to_json}\n\n"
      ].join

      stub_request(:post, described_class::API_URL)
        .to_return(status: 200, body: sse_body)

      chunks = []
      result = client.chat(params: base_params) { |c| chunks << c }

      expect(chunks).to include(
        { type: "thinking_start" },
        { type: "thinking", content: "hmm" },
        { type: "thinking_stop" }
      )
      expect(result.data[:thinking]).to eq("hmm")
    end

    it "returns failure on non-200 streaming response" do
      stub_request(:post, described_class::API_URL)
        .to_return(status: 401, body: { error: { message: "expired" } }.to_json)

      result = client.chat(params: base_params) { |_| }

      expect(result).not_to be_success
      expect(result.error).to include("401")
    end
  end
end
