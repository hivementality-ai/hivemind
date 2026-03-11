# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Providers::OllamaAdapter, type: :service do
  let(:config) { double("Config", base_url: nil) }
  let(:adapter) { described_class.new(config: config) }
  let(:messages) { [ { role: "user", content: "Hello, world!" } ] }
  let(:tools) { [] }
  let(:options) { {} }

  before do
    allow(adapter).to receive(:ollama_url).and_return("http://localhost:11434")
  end

  describe "#chat" do
    context "without tools" do
      it "makes a successful chat request" do
        stub_request(:post, "http://localhost:11434/api/chat")
          .with(body: hash_including(model: "llama3.2", messages: [ { role: "user", content: "Hello, world!" } ]))
          .to_return(
            status: 200,
            body: {
              message: { content: "Hello there!" },
              prompt_eval_count: 10,
              eval_count: 5
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

        stub_request(:post, "http://localhost:11434/api/chat")
          .with(body: hash_including(
            model: "llama3.2",
            messages: [ { role: "user", content: "Hello, world!" } ],
            tools: expected_tools
          ))
          .to_return(
            status: 200,
            body: {
              message: { content: "I'll help you with that!" },
              prompt_eval_count: 15,
              eval_count: 8
            }.to_json
          )

        result = adapter.chat(messages: messages, tools: tools, options: options)

        expect(result).to be_success
        expect(result.data[:content]).to eq("I'll help you with that!")
        expect(result.data[:tool_calls]).to be_nil
      end

      it "parses tool calls from response" do
        stub_request(:post, "http://localhost:11434/api/chat")
          .to_return(
            status: 200,
            body: {
              message: {
                content: "",
                tool_calls: [ {
                  function: { name: "shell", arguments: { command: "ls -la" } }
                } ]
              },
              prompt_eval_count: 15,
              eval_count: 12
            }.to_json
          )

        result = adapter.chat(messages: messages, tools: tools, options: options)

        expect(result).to be_success
        expect(result.data[:content]).to eq("")
        expect(result.data[:tool_calls]).to be_an(Array)
        expect(result.data[:tool_calls].first).to include(
          "name" => "shell",
          "input" => { "command" => "ls -la" }
        )
        expect(result.data[:tool_calls].first["id"]).to start_with("ollama_")
      end

      it "generates unique IDs for tool calls" do
        stub_request(:post, "http://localhost:11434/api/chat")
          .to_return(
            status: 200,
            body: {
              message: {
                content: "",
                tool_calls: [
                  { function: { name: "shell", arguments: { command: "ls" } } },
                  { function: { name: "shell", arguments: { command: "pwd" } } }
                ]
              },
              prompt_eval_count: 20,
              eval_count: 15
            }.to_json
          )

        result = adapter.chat(messages: messages, tools: tools, options: options)

        expect(result).to be_success
        expect(result.data[:tool_calls].length).to eq(2)
        ids = result.data[:tool_calls].map { |tc| tc["id"] }
        expect(ids).to all(start_with("ollama_"))
        expect(ids.uniq).to eq(ids) # All IDs should be unique
      end

      it "handles empty tool calls gracefully" do
        stub_request(:post, "http://localhost:11434/api/chat")
          .to_return(
            status: 200,
            body: {
              message: { content: "No tools needed", tool_calls: [] },
              prompt_eval_count: 10,
              eval_count: 5
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
          { role: "tool", tool_use_id: "call_123", content: "file1.txt\nfile2.txt" }
        ]
      end

      it "formats messages with tool calls correctly" do
        expected_messages = [
          { role: "user", content: "Run ls command" },
          {
            role: "assistant",
            content: "",
            tool_calls: [ { function: { name: "shell", arguments: { "command" => "ls" } } } ]
          },
          { role: "tool", content: "file1.txt\nfile2.txt" }
        ]

        stub_request(:post, "http://localhost:11434/api/chat")
          .with(body: hash_including(messages: expected_messages))
          .to_return(
            status: 200,
            body: {
              message: { content: "The files are listed above." },
              prompt_eval_count: 25,
              eval_count: 10
            }.to_json
          )

        result = adapter.chat(messages: messages_with_tool_calls, tools: [], options: options)

        expect(result).to be_success
        expect(result.data[:content]).to eq("The files are listed above.")
      end
    end

    context "streaming" do
      it "falls back to sync mode when tools are present" do
        tools = [ { name: "shell", description: "Run shell", input_schema: { type: "object" } } ]

        stub_request(:post, "http://localhost:11434/api/chat")
          .with(body: hash_including(
            tools: [ {
              type: "function",
              function: {
                name: "shell",
                description: "Run shell",
                parameters: { type: "object" }
              }
            } ]
          ))
          .to_return(
            status: 200,
            body: {
              message: { content: "Response without streaming" },
              prompt_eval_count: 10,
              eval_count: 5
            }.to_json
          )

        content_chunks = []
        result = adapter.chat(messages: messages, tools: tools, options: options) do |chunk|
          content_chunks << chunk[:content] if chunk[:type] == "content"
        end

        expect(result).to be_success
        expect(content_chunks.join).to eq("Response without streaming")
      end

      it "streams normally when no tools are present" do
        streaming_response = [
          '{"message":{"content":"Hello"}}',
          '{"message":{"content":" there"}}',
          '{"message":{"content":"!"}}',
          ""
        ].join("\n")

        stub_request(:post, "http://localhost:11434/api/chat")
          .with(body: hash_including(stream: true))
          .to_return(status: 200, body: streaming_response)

        content_chunks = []
        result = adapter.chat(messages: messages, tools: [], options: options) do |chunk|
          content_chunks << chunk[:content] if chunk[:type] == "content"
        end

        expect(result).to be_success
        expect(content_chunks).to eq([ "Hello", " there", "!" ])
        expect(result.data[:content]).to eq("Hello there!")
      end
    end

    context "with custom options" do
      let(:options) { { model: "llama3.1", temperature: 0.8, max_tokens: 100 } }

      it "uses custom model and options" do
        stub_request(:post, "http://localhost:11434/api/chat")
          .to_return(
            status: 200,
            body: { message: { content: "Custom response" } }.to_json
          )

        result = adapter.chat(messages: messages, tools: tools, options: options)

        expect(result).to be_success
        expect(result.data[:content]).to eq("Custom response")

        expect(WebMock).to have_requested(:post, "http://localhost:11434/api/chat")
          .with { |req|
            body = JSON.parse(req.body)
            body["model"] == "llama3.1" &&
              body["options"]["temperature"] == 0.8 &&
              body["options"]["num_predict"] == 100
          }
      end
    end

    context "num_ctx calculation" do
      it "includes num_ctx in API requests" do
        stub_request(:post, "http://localhost:11434/api/chat")
          .to_return(
            status: 200,
            body: { message: { content: "ok" }, prompt_eval_count: 5, eval_count: 3 }.to_json
          )

        result = adapter.chat(messages: messages, tools: tools, options: options)
        expect(result).to be_success

        expect(WebMock).to have_requested(:post, "http://localhost:11434/api/chat")
          .with { |req| JSON.parse(req.body)["options"].key?("num_ctx") }
      end

      it "uses a small num_ctx for short messages" do
        short_messages = [ { role: "user", content: "Hi" } ]

        stub_request(:post, "http://localhost:11434/api/chat")
          .to_return(
            status: 200,
            body: { message: { content: "Hey" } }.to_json
          )

        result = adapter.chat(messages: short_messages, tools: [], options: {})
        expect(result).to be_success

        expect(WebMock).to have_requested(:post, "http://localhost:11434/api/chat")
          .with { |req| JSON.parse(req.body)["options"]["num_ctx"] <= 8_192 }
      end

      it "scales num_ctx up for large conversations" do
        large_messages = [ { role: "user", content: "x" * 80_000 } ]

        stub_request(:post, "http://localhost:11434/api/chat")
          .to_return(
            status: 200,
            body: { message: { content: "ok" } }.to_json
          )

        result = adapter.chat(messages: large_messages, tools: [], options: {})
        expect(result).to be_success

        expect(WebMock).to have_requested(:post, "http://localhost:11434/api/chat")
          .with { |req| JSON.parse(req.body)["options"]["num_ctx"] > 8_192 }
      end

      it "factors tool schemas into num_ctx calculation" do
        large_tools = [
          {
            name: "tool1",
            description: "A" * 20_000,
            input_schema: { type: "object", properties: { x: { type: "string", description: "B" * 10_000 } } }
          }
        ]

        stub_request(:post, "http://localhost:11434/api/chat")
          .to_return(
            status: 200,
            body: { message: { content: "ok" } }.to_json
          )

        result = adapter.chat(messages: [ { role: "user", content: "hi" } ], tools: large_tools, options: {})
        expect(result).to be_success

        expect(WebMock).to have_requested(:post, "http://localhost:11434/api/chat")
          .with { |req| JSON.parse(req.body)["options"]["num_ctx"] > 8_192 }
      end
    end

    context "when API returns error" do
      it "handles connection errors gracefully" do
        stub_request(:post, "http://localhost:11434/api/chat")
          .to_raise(Faraday::ConnectionFailed.new("Connection refused"))

        result = adapter.chat(messages: messages, tools: tools, options: options)

        expect(result.success?).to be_falsey
        expect(result.error).to include("Ollama error")
      end
    end
  end

  describe "#models" do
    it "returns list of available models" do
      stub_request(:get, "http://localhost:11434/api/tags")
        .to_return(
          status: 200,
          body: {
            models: [
              { name: "llama3.2" },
              { name: "llama3.1" },
              { name: "codellama" }
            ]
          }.to_json
        )

      result = adapter.models

      expect(result).to be_success
      expect(result.data[:models]).to eq([ "llama3.2", "llama3.1", "codellama" ])
    end

    it "handles empty model list" do
      stub_request(:get, "http://localhost:11434/api/tags")
        .to_return(status: 200, body: {}.to_json)

      result = adapter.models

      expect(result).to be_success
      expect(result.data[:models]).to eq([])
    end
  end

  describe "#embed" do
    it "generates embeddings successfully" do
      stub_request(:post, "http://localhost:11434/api/embeddings")
        .with(body: hash_including(model: "nomic-embed-text", prompt: "test text"))
        .to_return(
          status: 200,
          body: { embedding: [ 0.1, 0.2, 0.3 ] }.to_json
        )

      result = adapter.embed(text: "test text")

      expect(result).to be_success
      expect(result.data[:embedding]).to eq([ 0.1, 0.2, 0.3 ])
    end

    it "uses custom model when specified" do
      stub_request(:post, "http://localhost:11434/api/embeddings")
        .with(body: hash_including(model: "custom-embed", prompt: "test"))
        .to_return(
          status: 200,
          body: { embedding: [ 0.4, 0.5 ] }.to_json
        )

      result = adapter.embed(text: "test", model: "custom-embed")

      expect(result).to be_success
      expect(result.data[:embedding]).to eq([ 0.4, 0.5 ])
    end
  end
end
