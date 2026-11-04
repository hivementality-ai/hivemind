# frozen_string_literal: true

require "rails_helper"

RSpec.describe TeamChats::AgentActivity do
  let(:agent) { create(:agent, name: "Alice") }
  let(:channel) { "team_chat_1" }

  before { allow(ActionCable.server).to receive(:broadcast) }

  describe ".track" do
    it "marks the agent thinking while the block runs and announces it" do
      status_inside = nil
      described_class.track(agent, channel: channel) { status_inside = agent.reload.status }

      expect(status_inside).to eq("thinking")
      expect(ActionCable.server).to have_received(:broadcast)
        .with(channel, hash_including(type: "agent_status", agent_id: agent.id, status: "thinking"))
    end

    it "sets the agent back to idle when the block finishes" do
      described_class.track(agent, channel: channel) { :done }

      expect(agent.reload).to be_idle
      expect(agent.current_task).to be_nil
      expect(ActionCable.server).to have_received(:broadcast)
        .with(channel, hash_including(type: "agent_status", status: "idle"))
    end

    it "sets the agent back to idle when the block raises" do
      expect { described_class.track(agent, channel: channel) { raise "provider down" } }
        .to raise_error("provider down")

      expect(agent.reload).to be_idle
    end

    it "returns the block's value" do
      expect(described_class.track(agent, channel: channel) { 42 }).to eq(42)
    end
  end

  describe ".working?" do
    it "is true for a fresh thinking status" do
      agent.update_columns(status: Agent.statuses[:thinking], updated_at: Time.current)

      expect(described_class.working?(agent)).to be true
    end

    it "is false once the status has gone stale" do
      agent.update_columns(status: Agent.statuses[:thinking], updated_at: (described_class::STALE_AFTER + 5).seconds.ago)

      expect(described_class.working?(agent)).to be false
    end

    it "is false for an idle agent" do
      expect(described_class.working?(agent)).to be false
    end
  end
end
