# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sessions::Chat do
  let(:agent) { create(:agent, name: "Test Agent", llm_model: "gpt-4o-mini", model_provider: "openai") }
  let(:session) { create(:session, agent: agent, session_key: "test-#{SecureRandom.hex(4)}") }
  let(:adapter) { instance_double(Providers::OpenaiAdapter) }
  let(:resolver_result) { ServiceResponse.success(data: { adapter: adapter }) }
  let(:message_result) { ServiceResponse.success(data: { messages: [{ "role" => "user", "content" => "Hello" }] }) }
  let(:llm_response) { ServiceResponse.success(data: { content: "Hi there!", usage: { input_tokens: 10, output_tokens: 5 } }) }

  before do
    allow(Providers::Resolver).to receive(:call).and_return(resolver_result)
    allow(Sessions::MessageBuilder).to receive(:call).and_return(message_result)
    allow(Sessions::PostProcessor).to receive(:call)
  end

  describe "orchestration budget enforcement" do
    it "blocks the LLM call when the session's delegation tree is over budget" do
      session.update!(metadata: { "orchestration_id" => "orch-123" })
      allow(Delegations::OrchestrationBudget).to receive(:exceeded?).with("orch-123").and_return(true)

      result = described_class.call(session: session, message: "Keep working")

      expect(result).not_to be_success
      expect(result.error).to match(/Orchestration budget exhausted/)
    end
  end

  describe "ToolLoop integration for non-OAuth providers" do
    let(:task_manager_tool) { create(:tool, name: "task_manager", executor_type: "task_manager", enabled: true, builtin: true) }
    let(:delegate_tool) { create(:tool, name: "delegate", executor_type: "delegate", enabled: true, builtin: true) }

    before do
      # Ensure tools exist as builtins
      allow(Tool).to receive_message_chain(:enabled, :builtin, :to_a).and_return([task_manager_tool, delegate_tool])
      allow(agent).to receive_message_chain(:agent_tools, :includes, :map).and_return([])
      allow(agent).to receive_message_chain(:skills, :enabled, :any?).and_return(false)
    end

    context "when tools are available and provider is NOT Anthropic OAuth" do
      let(:tool_loop_result) do
        ServiceResponse.success(data: {
          content: "Checked the board. 3 tasks in todo.",
          usage: { input_tokens: 100, output_tokens: 50 },
          tool_history: [{ tool: "task_manager", input: { action: "list" }, output: "3 tasks", success: true }]
        })
      end

      before do
        allow(Agents::ToolLoop).to receive(:call).and_return(tool_loop_result)
      end

      it "uses Agents::ToolLoop instead of direct adapter.chat" do
        result = described_class.call(session: session, message: "Check the board")

        expect(Agents::ToolLoop).to have_received(:call).with(
          hash_including(adapter: adapter, agent: agent, session: session)
        )
        expect(adapter).not_to have_received(:chat) if adapter.respond_to?(:chat)
      end

      it "returns tool_history in the result data" do
        result = described_class.call(session: session, message: "Check the board")

        expect(result).to be_success
        expect(result.data[:tool_history]).to be_present
        expect(result.data[:tool_history].first[:tool]).to eq("task_manager")
      end

      it "stores tool_calls in the transcript entry" do
        described_class.call(session: session, message: "Check the board")

        transcript = session.reload.transcript
        assistant_entry = transcript.find { |e| e["role"] == "assistant" }
        expect(assistant_entry["tool_calls"]).to be_present
      end

      it "updates token counts from ToolLoop usage" do
        described_class.call(session: session, message: "Check the board")

        session.reload
        expect(session.input_tokens).to eq(100)
        expect(session.output_tokens).to eq(50)
      end
    end

    context "when no tools are available" do
      before do
        allow(Tool).to receive_message_chain(:enabled, :builtin, :to_a).and_return([])
        allow(adapter).to receive(:chat).and_return(llm_response)
        # Stub is_a? check for OAuth detection
        allow(adapter).to receive(:is_a?).with(Providers::AnthropicAdapter).and_return(false)
        allow(Agents::ToolLoop).to receive(:call)
      end

      it "falls back to direct adapter.chat" do
        result = described_class.call(session: session, message: "Hello")

        expect(adapter).to have_received(:chat)
        expect(Agents::ToolLoop).not_to have_received(:call) if defined?(Agents::ToolLoop) && Agents::ToolLoop.respond_to?(:call)
      end
    end
  end
end
