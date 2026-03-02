# frozen_string_literal: true

require "rails_helper"

RSpec.describe Providers::Anthropic::GemClient, type: :service do
  subject(:gem_client) { described_class.new }

  let(:client) { instance_double("Anthropic::Client") }
  let(:messages_api) { instance_double("messages_api") }
  let(:params) { { model: "claude-sonnet-4-5", messages: [{ role: "user", content: "Hello" }], max_tokens: 8192 } }

  before do
    allow(client).to receive(:messages).and_return(messages_api)
  end

  describe "#chat" do
    context "streaming (block given)" do
      it "yields content chunks and returns accumulated content" do
        events = [
          build_event("content_block_delta", delta: build_delta(text: "Hello ")),
          build_event("content_block_delta", delta: build_delta(text: "world!"))
        ]
        stream = instance_double("stream")
        allow(messages_api).to receive(:stream).and_return(stream)
        allow(stream).to receive(:each).and_yield(events[0]).and_yield(events[1])

        chunks = []
        result = gem_client.chat(client:, params:) { |chunk| chunks << chunk }

        expect(result).to be_success
        expect(result.data[:content]).to eq("Hello world!")
        expect(chunks).to contain_exactly(
          { type: "content", content: "Hello " },
          { type: "content", content: "world!" }
        )
      end

      it "handles thinking blocks" do
        events = [
          build_event("content_block_start", content_block: build_content_block("thinking")),
          build_event("content_block_delta", delta: build_delta(thinking: "Let me think...")),
          build_event("content_block_stop"),
          build_event("content_block_start", content_block: build_content_block("text")),
          build_event("content_block_delta", delta: build_delta(text: "Answer")),
          build_event("content_block_stop")
        ]

        stream = instance_double("stream")
        allow(messages_api).to receive(:stream).and_return(stream)
        yielder = allow(stream).to receive(:each)
        events.each { |e| yielder = yielder.and_yield(e) }

        chunks = []
        result = gem_client.chat(client:, params:) { |chunk| chunks << chunk }

        expect(result).to be_success
        expect(result.data[:thinking]).to eq("Let me think...")
        expect(result.data[:content]).to eq("Answer")
        expect(chunks).to include(
          { type: "thinking_start" },
          { type: "thinking", content: "Let me think..." },
          { type: "thinking_stop" },
          { type: "content", content: "Answer" }
        )
      end

      it "extracts usage from message_start and message_delta events" do
        events = [
          build_event("message_start", message: build_message_usage(input_tokens: 100, cache_creation: 10, cache_read: 20)),
          build_event("content_block_delta", delta: build_delta(text: "Hi")),
          build_event("message_delta", usage: build_usage(output_tokens: 50))
        ]

        stream = instance_double("stream")
        allow(messages_api).to receive(:stream).and_return(stream)
        yielder = allow(stream).to receive(:each)
        events.each { |e| yielder = yielder.and_yield(e) }

        result = gem_client.chat(client:, params:) { |_| }

        expect(result.data[:usage]).to include(
          input_tokens: 100,
          output_tokens: 50,
          cache_creation_input_tokens: 10,
          cache_read_input_tokens: 20
        )
      end

      it "returns nil thinking when no thinking content" do
        events = [
          build_event("content_block_delta", delta: build_delta(text: "Just text"))
        ]
        stream = instance_double("stream")
        allow(messages_api).to receive(:stream).and_return(stream)
        allow(stream).to receive(:each).and_yield(events[0])

        result = gem_client.chat(client:, params:) { |_| }

        expect(result.data[:thinking]).to be_nil
      end
    end

    context "sync (no block)" do
      it "returns text content" do
        response = build_sync_response(
          content: [build_text_block("Hello!")],
          usage: build_response_usage(input: 10, output: 5)
        )
        allow(messages_api).to receive(:create).and_return(response)

        result = gem_client.chat(client:, params:)

        expect(result).to be_success
        expect(result.data[:content]).to eq("Hello!")
        expect(result.data[:tool_calls]).to be_nil
      end

      it "returns tool calls" do
        tool_block = build_tool_use_block(id: "tool_1", name: "shell", input: { "command" => "ls" })
        response = build_sync_response(
          content: [tool_block],
          usage: build_response_usage(input: 15, output: 8)
        )
        allow(messages_api).to receive(:create).and_return(response)

        result = gem_client.chat(client:, params:)

        expect(result).to be_success
        expect(result.data[:tool_calls]).to eq([
          { "id" => "tool_1", "name" => "shell", "input" => { "command" => "ls" } }
        ])
      end

      it "returns thinking content" do
        response = build_sync_response(
          content: [build_thinking_block("Deep thought"), build_text_block("42")],
          usage: build_response_usage(input: 20, output: 10)
        )
        allow(messages_api).to receive(:create).and_return(response)

        result = gem_client.chat(client:, params:)

        expect(result).to be_success
        expect(result.data[:thinking]).to eq("Deep thought")
        expect(result.data[:content]).to eq("42")
      end

      it "extracts usage with cache tokens" do
        response = build_sync_response(
          content: [build_text_block("Hi")],
          usage: build_response_usage(input: 100, output: 50, cache_creation: 10, cache_read: 20)
        )
        allow(messages_api).to receive(:create).and_return(response)

        result = gem_client.chat(client:, params:)

        expect(result.data[:usage]).to include(
          input_tokens: 100,
          output_tokens: 50,
          cache_creation_input_tokens: 10,
          cache_read_input_tokens: 20
        )
      end
    end
  end

  # ─── Test helpers ───

  def build_event(type, **attrs)
    event = double("event", type: type)

    case type
    when "content_block_start"
      allow(event).to receive(:respond_to?).with(:content_block).and_return(attrs.key?(:content_block))
      allow(event).to receive(:content_block).and_return(attrs[:content_block]) if attrs[:content_block]
    when "content_block_delta"
      allow(event).to receive(:delta).and_return(attrs[:delta])
    when "content_block_stop"
      # no extra attrs
    when "message_start"
      allow(event).to receive(:message).and_return(attrs[:message])
    when "message_delta"
      allow(event).to receive(:respond_to?).with(:usage).and_return(attrs.key?(:usage))
      allow(event).to receive(:usage).and_return(attrs[:usage])
    end

    event
  end

  def build_delta(text: nil, thinking: nil)
    delta = double("delta")
    allow(delta).to receive(:respond_to?).with(:thinking).and_return(!thinking.nil?)
    allow(delta).to receive(:thinking).and_return(thinking)
    allow(delta).to receive(:respond_to?).with(:text).and_return(!text.nil?)
    allow(delta).to receive(:text).and_return(text)
    delta
  end

  def build_content_block(type)
    double("content_block", type: type)
  end

  def build_message_usage(input_tokens:, cache_creation: nil, cache_read: nil)
    usage = double("usage", input_tokens: input_tokens)
    allow(usage).to receive(:respond_to?).with(:cache_creation_input_tokens).and_return(!cache_creation.nil?)
    allow(usage).to receive(:cache_creation_input_tokens).and_return(cache_creation)
    allow(usage).to receive(:respond_to?).with(:cache_read_input_tokens).and_return(!cache_read.nil?)
    allow(usage).to receive(:cache_read_input_tokens).and_return(cache_read)

    message = double("message")
    allow(message).to receive(:respond_to?).with(:usage).and_return(true)
    allow(message).to receive(:usage).and_return(usage)
    message
  end

  def build_usage(output_tokens:)
    double("usage", output_tokens: output_tokens)
  end

  def build_sync_response(content:, usage:)
    double("response", content: content, usage: usage)
  end

  def build_response_usage(input:, output:, cache_creation: nil, cache_read: nil)
    usage = double("usage", input_tokens: input, output_tokens: output)
    allow(usage).to receive(:respond_to?).with(:cache_creation_input_tokens).and_return(!cache_creation.nil?)
    allow(usage).to receive(:cache_creation_input_tokens).and_return(cache_creation)
    allow(usage).to receive(:respond_to?).with(:cache_read_input_tokens).and_return(!cache_read.nil?)
    allow(usage).to receive(:cache_read_input_tokens).and_return(cache_read)
    usage
  end

  def build_text_block(text)
    double("block", type: "text", text: text)
  end

  def build_thinking_block(thinking)
    block = double("block", type: "thinking")
    allow(block).to receive(:respond_to?).with(:thinking).and_return(true)
    allow(block).to receive(:thinking).and_return(thinking)
    block
  end

  def build_tool_use_block(id:, name:, input:)
    double("block", type: "tool_use", id: id, name: name, input: double(to_h: input, stringify_keys: input))
  end
end
