# frozen_string_literal: true

require "rails_helper"

RSpec.describe HeartbeatJob, type: :job do
  let(:agent) { create(:agent, name: "System Assistant", llm_model: "claude-3-5-sonnet", system_agent: true) }
  let(:config) { { "enabled" => true, "interval_minutes" => 30 }.to_json }
  let(:chat_result) { double(success?: true, data: { reply: "Everything looks good" }) }

  before do
    allow(ActionCable.server).to receive(:broadcast)
    allow(Agent).to receive(:system_assistant).and_return(agent)
    allow(Setting).to receive(:get).with("heartbeat").and_return(config)
    allow(Setting).to receive(:get).with("heartbeat_last_run").and_return(nil)
    allow(Setting).to receive(:get).with("heartbeat_tasks").and_return(nil)
    allow(Setting).to receive(:set)
    allow(Sessions::Chat).to receive(:call).and_return(chat_result)
  end

  describe "#perform" do
    it "skips when config not enabled" do
      allow(Setting).to receive(:get).with("heartbeat").and_return({ "enabled" => false }.to_json)
      described_class.perform_now
      expect(Sessions::Chat).not_to have_received(:call)
    end

    it "skips when not due yet" do
      allow(Setting).to receive(:get).with("heartbeat_last_run").and_return(5.minutes.ago.iso8601)
      described_class.perform_now
      expect(Sessions::Chat).not_to have_received(:call)
    end

    it "runs when due and updates last_run" do
      described_class.perform_now
      expect(Setting).to have_received(:set).with("heartbeat_last_run", anything)
      expect(Sessions::Chat).to have_received(:call)
    end

    it "broadcasts reply via ActionCable" do
      described_class.perform_now
      expect(ActionCable.server).to have_received(:broadcast).with(
        anything,
        hash_including(type: "heartbeat", content: "Everything looks good")
      )
    end

    it "suppresses HEARTBEAT_OK responses" do
      allow(Sessions::Chat).to receive(:call).and_return(double(success?: true, data: { reply: "HEARTBEAT_OK" }))
      described_class.perform_now
      expect(ActionCable.server).not_to have_received(:broadcast)
    end

    it "overrides model if config specifies one and restores after" do
      config_with_model = { "enabled" => true, "interval_minutes" => 30, "model" => "gpt-4" }.to_json
      allow(Setting).to receive(:get).with("heartbeat").and_return(config_with_model)

      described_class.perform_now

      expect(agent.reload.llm_model).to eq("claude-3-5-sonnet")
    end

    it "builds prompt with tasks" do
      allow(Setting).to receive(:get).with("heartbeat_tasks").and_return([ { "task" => "Check email" } ].to_json)
      described_class.perform_now
      expect(Sessions::Chat).to have_received(:call).with(hash_including(message: a_string_including("Check email")))
    end

    it "includes teammates in prompt" do
      create(:agent, name: "Helper", role: "Developer", enabled: true)
      described_class.perform_now
      expect(Sessions::Chat).to have_received(:call).with(hash_including(message: a_string_including("Helper")))
    end

    it "handles errors gracefully" do
      allow(Sessions::Chat).to receive(:call).and_raise(StandardError, "boom")
      expect { described_class.perform_now }.not_to raise_error
    end
  end
end
