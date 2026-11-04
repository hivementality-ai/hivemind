# frozen_string_literal: true

require "rails_helper"

RSpec.describe Providers::OpenaiAdapter, type: :service do
  let(:config) { double("Config", base_url: nil) }
  let(:adapter) { described_class.new(config: config, api_key: "sk-test") }
  let(:client) { double("OpenAI::Client") }
  let(:tools) { [ { name: "shell", description: "Run shell", input_schema: { type: "object" } } ] }
  let(:messages) { [ { role: "user", content: "hi" } ] }

  before { allow(adapter).to receive(:build_client).and_return(client) }

  def tool_delta(payload)
    { "choices" => [ { "delta" => { "tool_calls" => [ payload ] } } ] }
  end

  describe "#chat streaming with tools" do
    it "assembles index-keyed tool calls from fragmented deltas" do
      chunks = [
        { "choices" => [ { "delta" => { "content" => "On it." } } ] },
        tool_delta({ "index" => 0, "id" => "call_a", "function" => { "name" => "shell", "arguments" => "" } }),
        tool_delta({ "index" => 0, "function" => { "arguments" => "{\"comm" } }),
        tool_delta({ "index" => 1, "id" => "call_b", "function" => { "name" => "shell", "arguments" => "{\"command\":\"pwd\"}" } }),
        tool_delta({ "index" => 0, "function" => { "arguments" => "and\":" } }),
        tool_delta({ "index" => 0, "function" => { "arguments" => "\"ls\"}" } })
      ]
      allow(client).to receive(:chat) { |parameters:| chunks.each { |c| parameters[:stream].call(c) } }

      content = []
      result = adapter.chat(messages: messages, tools: tools) { |c| content << c[:content] if c[:type] == "content" }

      expect(result).to be_success
      expect(content.join).to eq("On it.")
      expect(result.data[:tool_calls]).to eq(
        [
          { "id" => "call_a", "name" => "shell", "input" => { "command" => "ls" } },
          { "id" => "call_b", "name" => "shell", "input" => { "command" => "pwd" } }
        ]
      )
    end

    it "returns no tool calls when the stream carries none" do
      allow(client).to receive(:chat) do |parameters:|
        parameters[:stream].call({ "choices" => [ { "delta" => { "content" => "Just text" } } ] })
      end

      result = adapter.chat(messages: messages, tools: tools) { |_| }

      expect(result.data[:content]).to eq("Just text")
      expect(result.data[:tool_calls]).to be_nil
    end
  end
end
