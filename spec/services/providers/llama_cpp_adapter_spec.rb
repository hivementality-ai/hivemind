# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Providers::LlamaCppAdapter, type: :service do
  let(:config) { double("Config", base_url: nil) }
  let(:adapter) { described_class.new(config: config) }
  let(:messages) { [ { role: "user", content: "Hello, world!" } ] }
  let(:tools) { [] }
  let(:options) { {} }

  before do
    allow(adapter).to receive(:llama_cpp_url).and_return("http://localhost:8080")
  end

  describe "#chat" do
    context "without tools" do
      it "makes a successful chat request" do
        stub_request(:post, "http://localhost:8080/v1/chat/completions")
          .with(body: hash_including(model: "default", messages: [ { role: "user", content: "Hello, world!" } ]))
          .to_return(
            status: 200,
            body: {
              choices: [ { message: { content: "Hello there!" } } ],
              usage: { prompt_tokens: 10, completion_tokens: 5 }
            }.to_json
          )

        result = adapter.chat(messages: messages, tools: tools, options: options)

        expect(result).to be_success
        expect(result.data[:content]).to eq("Hello there!")
        expect(result.data[:tool_calls]).to be_nil
        expect(result.data[:usage]).to include(input_tokens: 10, output_tokens: 5)
      end
    end

    context "with tools" do
      let(:tools) do
        [
          {
            name: "shell",
            description: "Run a shell command",
            input_schema: {
              type: "object",
              properties: { command: { type: "string", description: "Command to run" } },
              required: [ "command" ]
            }
          }
        ]
      end

      it "includes tools in the request" do
        expected_tools = [ {
          type: "function",
          function: {
            name: "shell",
            description: "Run a shell command",
            parameters: {
              type: "object",
              properties: { command: { type: "string", description: "Command to run" } },
              required: [ "command" ]
            }
          }
        } ]

        stub_request(:post, "http://localhost:8080/v1/chat/completions")
          .with(body: hash_including(
            model: "default",
            messages: [ { role: "user", content: "Hello, world!" } ],
            tools: expected_tools
          ))
          .to_return(
            status: 200,
            body: {
              choices: [ { message: { content: "I'll help you with that!" } } ],
              usage: { prompt_tokens: 15, completion_tokens: 8 }
            }.to_json
          )

        result = adapter.chat(messages: messages, tools: tools, options: options)

        expect(result).to be_success
        expect(result.data[:content]).to eq("I'll help you with that!")
        expect(result.data[:tool_calls]).to be_nil
      end

      it "parses tool calls from response" do
        stub_request(:post, "http://localhost:8080/v1/chat/completions")
          .to_return(
            status: 200,
            body: {
              choices: [ {
                message: {
                  content: "",
                  tool_calls: [ {
                    id: "call_abc123",
                    type: "function",
                    function: { name: "shell", arguments: '{"command":"ls -la"}' }
                  } ]
                }
              } ],
              usage: { prompt_tokens: 15, completion_tokens: 12 }
            }.to_json
          )

        result = adapter.chat(messages: messages, tools: tools, options: options)

        expect(result).to be_success
        expect(result.data[:content]).to eq("")
        expect(result.data[:tool_calls]).to be_an(Array)
        expect(result.data[:tool_calls].first).to include(
          "id" => "call_abc123",
          "name" => "shell",
          "input" => { "command" => "ls -la" }
        )
      end

      it "generates IDs for tool calls without them" do
        stub_request(:post, "http://localhost:8080/v1/chat/completions")
          .to_return(
            status: 200,
            body: {
              choices: [ {
                message: {
                  content: "",
                  tool_calls: [
                    { type: "function", function: { name: "shell", arguments: '{"command":"ls"}' } },
                    { type: "function", function: { name: "shell", arguments: '{"command":"pwd"}' } }
                  ]
                }
              } ],
              usage: { prompt_tokens: 20, completion_tokens: 15 }
            }.to_json
          )

        result = adapter.chat(messages: messages, tools: tools, options: options)

        expect(result).to be_success
        expect(result.data[:tool_calls].length).to eq(2)
        ids = result.data[:tool_calls].map { |tc| tc["id"] }
        expect(ids).to all(start_with("llamacpp_"))
        expect(ids.uniq).to eq(ids)
      end

      it "handles empty tool calls gracefully" do
        stub_request(:post, "http://localhost:8080/v1/chat/completions")
          .to_return(
            status: 200,
            body: {
              choices: [ { message: { content: "No tools needed", tool_calls: [] } } ],
              usage: { prompt_tokens: 10, completion_tokens: 5 }
            }.to_json
          )

        result = adapter.chat(messages: messages, tools: tools, options: options)

        expect(result).to be_success
        expect(result.data[:tool_calls]).to be_nil
      end
    end

    context "with messages containing tool calls" do
      let(:messages_with_tool_calls) do
        [
          { role: "user", content: "Run ls command" },
          {
            role: "assistant",
            content: "",
            tool_calls: [ { "id" => "call_123", "name" => "shell", "input" => { "command" => "ls" } } ]
          },
          { role: "tool", tool_call_id: "call_123", content: "file1.txt\nfile2.txt" }
        ]
      end

      it "formats messages with tool calls correctly" do
        stub_request(:post, "http://localhost:8080/v1/chat/completions")
          .to_return(
            status: 200,
            body: {
              choices: [ { message: { content: "The files are listed above." } } ],
              usage: { prompt_tokens: 25, completion_tokens: 10 }
            }.to_json
          )

        result = adapter.chat(messages: messages_with_tool_calls, tools: [], options: options)

        expect(result).to be_success
        expect(result.data[:content]).to eq("The files are listed above.")

        expect(WebMock).to have_requested(:post, "http://localhost:8080/v1/chat/completions")
          .with { |req|
            body = JSON.parse(req.body)
            msgs = body["messages"]
            # Check assistant message has OpenAI-style tool_calls
            assistant_msg = msgs.find { |m| m["role"] == "assistant" }
            assistant_msg["tool_calls"].first["type"] == "function" &&
              assistant_msg["tool_calls"].first["function"]["name"] == "shell" &&
              # Check tool message has tool_call_id
              msgs.find { |m| m["role"] == "tool" }["tool_call_id"] == "call_123"
          }
      end
    end

    context "streaming" do
      it "falls back to sync mode when tools are present" do
        tools = [ { name: "shell", description: "Run shell", input_schema: { type: "object" } } ]

        stub_request(:post, "http://localhost:8080/v1/chat/completions")
          .to_return(
            status: 200,
            body: {
              choices: [ { message: { content: "Response without streaming" } } ],
              usage: { prompt_tokens: 10, completion_tokens: 5 }
            }.to_json
          )

        content_chunks = []
        result = adapter.chat(messages: messages, tools: tools, options: options) do |chunk|
          content_chunks << chunk[:content] if chunk[:type] == "content"
        end

        expect(result).to be_success
        expect(content_chunks.join).to eq("Response without streaming")
      end
    end

    context "with custom options" do
      let(:options) { { model: "my-model", temperature: 0.8, max_tokens: 100 } }

      it "uses custom model and options" do
        stub_request(:post, "http://localhost:8080/v1/chat/completions")
          .to_return(
            status: 200,
            body: { choices: [ { message: { content: "Custom response" } } ] }.to_json
          )

        result = adapter.chat(messages: messages, tools: tools, options: options)

        expect(result).to be_success
        expect(result.data[:content]).to eq("Custom response")

        expect(WebMock).to have_requested(:post, "http://localhost:8080/v1/chat/completions")
          .with { |req|
            body = JSON.parse(req.body)
            body["model"] == "my-model" &&
              body["temperature"] == 0.8 &&
              body["max_tokens"] == 100
          }
      end
    end

    context "when API returns error" do
      it "handles connection errors gracefully" do
        stub_request(:post, "http://localhost:8080/v1/chat/completions")
          .to_raise(Faraday::ConnectionFailed.new("Connection refused"))

        result = adapter.chat(messages: messages, tools: tools, options: options)

        expect(result.success?).to be_falsey
        expect(result.error).to include("llama.cpp error")
      end
    end
  end

  describe "#models" do
    it "returns list of available models" do
      stub_request(:get, "http://localhost:8080/v1/models")
        .to_return(
          status: 200,
          body: {
            data: [
              { id: "my-model", object: "model" },
              { id: "another-model", object: "model" }
            ]
          }.to_json
        )

      result = adapter.models

      expect(result).to be_success
      expect(result.data[:models]).to eq([ "my-model", "another-model" ])
    end

    it "handles empty model list" do
      stub_request(:get, "http://localhost:8080/v1/models")
        .to_return(status: 200, body: {}.to_json)

      result = adapter.models

      expect(result).to be_success
      expect(result.data[:models]).to eq([])
    end

    it "handles connection errors" do
      stub_request(:get, "http://localhost:8080/v1/models")
        .to_raise(Faraday::ConnectionFailed.new("Connection refused"))

      result = adapter.models

      expect(result.success?).to be_falsey
      expect(result.error).to include("Failed to list models")
    end
  end

  describe "#embed" do
    it "generates embeddings successfully" do
      stub_request(:post, "http://localhost:8080/v1/embeddings")
        .with(body: hash_including(model: "default", input: "test text"))
        .to_return(
          status: 200,
          body: { data: [ { embedding: [ 0.1, 0.2, 0.3 ] } ] }.to_json
        )

      result = adapter.embed(text: "test text")

      expect(result).to be_success
      expect(result.data[:embedding]).to eq([ 0.1, 0.2, 0.3 ])
    end

    it "uses custom model when specified" do
      stub_request(:post, "http://localhost:8080/v1/embeddings")
        .with(body: hash_including(model: "custom-embed", input: "test"))
        .to_return(
          status: 200,
          body: { data: [ { embedding: [ 0.4, 0.5 ] } ] }.to_json
        )

      result = adapter.embed(text: "test", model: "custom-embed")

      expect(result).to be_success
      expect(result.data[:embedding]).to eq([ 0.4, 0.5 ])
    end

    it "handles embedding errors" do
      stub_request(:post, "http://localhost:8080/v1/embeddings")
        .to_raise(Faraday::ConnectionFailed.new("Connection refused"))

      result = adapter.embed(text: "test")

      expect(result.success?).to be_falsey
      expect(result.error).to include("Embedding error")
    end
  end
end
