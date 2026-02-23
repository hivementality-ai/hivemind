# frozen_string_literal: true

require "rails_helper"

RSpec.describe InboundMessageJob, type: :job do
  let(:agent) { create(:agent, name: "TestBot", enabled: true) }
  let(:adapter) { double("ChannelAdapter", send_message: true) }
  let(:chat_result) { double(success?: true, data: { reply: "Hello back!" }) }
  let(:hashtag_no_bypass) do
    HashtagActions::Processor::ProcessResult.new(
      bypass_llm: false, response: nil, clean_message: "Hello", prompt_addons: [], side_effects: []
    )
  end

  before do
    allow(ActionCable.server).to receive(:broadcast)
    allow(Channels::Registry).to receive(:adapter_for).and_return(adapter)
    allow(Sessions::Chat).to receive(:call).and_return(chat_result)
    allow(HashtagActions::Processor).to receive(:call).and_return(hashtag_no_bypass)
  end

  describe "#perform" do
    context "Slack routing" do
      let(:channel) { create(:channel, :slack) }
      let(:message) { create(:inbound_message, channel: channel, content: "Hello", metadata: {}) }

      before do
        allow(Channels::MessageRouter).to receive(:call).and_return(
          double(success?: true, data: { agent: agent })
        )
      end

      it "uses MessageRouter for Slack channels" do
        described_class.perform_now(message.id)
        expect(Channels::MessageRouter).to have_received(:call).with(channel: channel, message: message)
      end

      it "sends response without name prefix for Slack" do
        described_class.perform_now(message.id)
        expect(adapter).to have_received(:send_message).with(
          hash_including(content: "Hello back!")
        )
      end

      it "tracks thread when thread_ts present" do
        message.update!(metadata: { "thread_ts" => "123.456" })
        allow(ChannelThread).to receive(:claim_thread)
        described_class.perform_now(message.id)
        expect(ChannelThread).to have_received(:claim_thread).with(channel: channel, agent: agent, thread_id: "123.456")
      end

      it "warns when no agent found" do
        allow(Channels::MessageRouter).to receive(:call).and_return(
          double(success?: true, data: { agent: nil })
        )
        expect(Rails.logger).to receive(:warn).with(a_string_including("No agent found"))
        described_class.perform_now(message.id)
      end
    end

    context "legacy routing with @mentions" do
      let(:channel) { create(:channel, :telegram) }

      it "routes to mentioned agent" do
        message = create(:inbound_message, channel: channel, content: "@#{agent.name} Hello")
        described_class.perform_now(message.id)
        expect(Sessions::Chat).to have_received(:call)
        expect(adapter).to have_received(:send_message).with(
          hash_including(content: a_string_matching(/.+/))
        )
      end

      it "routes to mentioned team" do
        create(:user) unless User.any?
        team = create(:team, name: "DevTeam")
        agent.update!(team: team, enabled: true)
        message = create(:inbound_message, channel: channel, content: "@DevTeam Fix this")
        described_class.perform_now(message.id)
        expect(TeamChatSession.count).to be >= 1
      end
    end

    context "default routing" do
      let(:channel) { create(:channel, :telegram, config: { "default_agent_id" => agent.id }) }
      let(:message) { create(:inbound_message, channel: channel, content: "Hello") }

      it "falls back to default_agent from channel config" do
        described_class.perform_now(message.id)
        expect(Sessions::Chat).to have_received(:call)
      end

      it "falls back to default_team from channel config" do
        create(:user) unless User.any?
        team = create(:team, name: "Default")
        agent.update!(team: team, enabled: true)
        channel.update!(config: { "default_team_id" => team.id })
        message = create(:inbound_message, channel: channel, content: "Hello")
        described_class.perform_now(message.id)
        expect(TeamChatSession.count).to be >= 1
      end
    end

    context "team routing" do
      let(:team) { create(:team, name: "MyTeam") }
      let(:channel) { create(:channel, :telegram) }
      let(:message) { create(:inbound_message, channel: channel, content: "@MyTeam Build it") }

      before do
        agent.update!(team: team, enabled: true)
        create(:user) unless User.any?
      end

      it "creates TeamChatSession for team routing" do
        described_class.perform_now(message.id)
        expect(TeamChatSession.count).to be >= 1
      end
    end

    context "no routing target" do
      let(:channel) { create(:channel, :telegram, config: {}) }
      let(:message) { create(:inbound_message, channel: channel, content: "Hello") }

      before { Agent.where.not(id: agent.id).destroy_all; agent.update!(enabled: false) }

      it "logs warning when no target found" do
        expect(Rails.logger).to receive(:warn).with(a_string_including("No routing target"))
        described_class.perform_now(message.id)
      end
    end

    context "hashtag bypass in agent routing" do
      let(:channel) { create(:channel, :telegram, config: { "default_agent_id" => agent.id }) }
      let(:message) { create(:inbound_message, channel: channel, content: "#help") }

      before do
        allow(HashtagActions::Processor).to receive(:call).and_return(
          HashtagActions::Processor::ProcessResult.new(
            bypass_llm: true, response: "Help info", clean_message: "", prompt_addons: [], side_effects: []
          )
        )
      end

      it "sends hashtag response without calling LLM" do
        described_class.perform_now(message.id)
        expect(Sessions::Chat).not_to have_received(:call)
        expect(adapter).to have_received(:send_message).with(hash_including(content: a_string_including("Help info")))
      end
    end

    context "error handling" do
      let(:channel) { create(:channel, :telegram) }
      let(:message) { create(:inbound_message, channel: channel, content: "Hello") }

      it "rescues and logs errors" do
        allow(InboundMessage).to receive(:find).and_raise(StandardError, "DB error")
        expect(Rails.logger).to receive(:error).with(a_string_including("DB error"))
        described_class.perform_now(message.id)
      end
    end
  end
end
