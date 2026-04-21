# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::Executor, "signal propagation" do
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent) }
  let(:sleep_tool) { create(:tool, executor_type: "sleep", name: "sleep") }

  before do
    allow(Plugins::Hooks).to receive(:trigger)
  end

  context "when executor raises AgentInterrupted" do
    before do
      allow_any_instance_of(Tools::SleepExecutor).to receive(:call)
        .and_raise(AgentInterrupted)
    end

    it "propagates the exception instead of swallowing it" do
      expect {
        described_class.call(
          tool: sleep_tool,
          input: { "seconds" => 10 },
          agent: agent,
          session: session
        )
      }.to raise_error(AgentInterrupted)
    end
  end

  context "when executor raises AgentRedirected" do
    before do
      allow_any_instance_of(Tools::SleepExecutor).to receive(:call)
        .and_raise(AgentRedirected.new("do something else"))
    end

    it "propagates the exception instead of swallowing it" do
      expect {
        described_class.call(
          tool: sleep_tool,
          input: { "seconds" => 10 },
          agent: agent,
          session: session
        )
      }.to raise_error(AgentRedirected)
    end
  end

  context "when executor raises a regular StandardError" do
    before do
      allow_any_instance_of(Tools::SleepExecutor).to receive(:call)
        .and_raise(StandardError, "something broke")
    end

    it "catches the error and returns a failure response" do
      result = described_class.call(
        tool: sleep_tool,
        input: { "seconds" => 10 },
        agent: agent,
        session: session
      )

      expect(result.success?).to be false
      expect(result.error).to eq("something broke")
    end

    it "records the failure on the execution record" do
      described_class.call(
        tool: sleep_tool,
        input: { "seconds" => 10 },
        agent: agent,
        session: session
      )

      execution = ToolExecution.last
      expect(execution.status).to eq("failed")
      expect(execution.error).to eq("something broke")
    end
  end
end
