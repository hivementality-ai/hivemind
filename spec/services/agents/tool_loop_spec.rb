# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::ToolLoop do
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent) }
  let(:tool) { double("Tool", name: "shell", to_llm_tool: { name: "shell", description: "Run", input_schema: { type: "object" } }) }
  let(:tool_call) { { "id" => "call_1", "name" => "shell", "input" => { "command" => "ls" } } }
  let(:adapter) { double("Adapter") }
  let(:tokens) { [] }

  before do
    allow(ActionCable.server).to receive(:broadcast) { |_, payload| tokens << payload[:content] if payload[:type] == "token" }
    allow(SessionSignal).to receive(:check).and_return(nil)
    allow(Tools::Executor).to receive(:call).and_return(ServiceResponse.success(data: { output: "done" }))
  end

  def run_loop(&block)
    described_class.call(adapter:, agent:, session:, messages: [ { role: "user", content: "hi" } ], tools: [ tool ], channel: "session_test", &block)
  end

  context "with a delta block" do
    before do
      rounds = [
        [ [ "Let me ", "look." ], ServiceResponse.success(data: { content: "Let me look.", tool_calls: [ tool_call ], usage: {} }) ],
        [ [ "All done" ], ServiceResponse.success(data: { content: "All done", tool_calls: nil, usage: {} }) ]
      ]
      allow(adapter).to receive(:chat) do |**, &stream|
        deltas, response = rounds.shift
        deltas.each { |d| stream&.call({ type: "content", content: d }) }
        response
      end
    end

    it "yields text deltas from the tool round and the final round" do
      deltas = []
      result = run_loop { |d| deltas << d }

      expect(deltas).to eq([ "Let me ", "look.", "All done" ])
      expect(result.data[:content]).to eq("All done")
    end

    it "broadcasts each streamed delta exactly once" do
      run_loop { |_| }

      expect(tokens).to eq([ "Let me ", "look.", "All done" ])
    end
  end

  context "without a delta block" do
    it "calls the adapter without a block and broadcasts the whole answer" do
      streamed = nil
      allow(adapter).to receive(:chat) do |**, &stream|
        streamed = !stream.nil?
        ServiceResponse.success(data: { content: "Plain", tool_calls: nil, usage: {} })
      end

      run_loop

      expect(streamed).to be(false)
      expect(tokens).to eq([ "Plain" ])
    end
  end
end
