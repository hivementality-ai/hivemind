# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::MessageRouter, type: :service do
  let(:slack_channel) { create(:channel, channel_type: "slack") }
  let(:agent1) { create(:agent, name: "Agent One", enabled: true) }
  let(:agent2) { create(:agent, name: "Agent Two", enabled: true) }
  let(:disabled_agent) { create(:agent, name: "Disabled Agent", enabled: false) }

  describe ".call" do
    subject { described_class.call(channel: slack_channel, message: message) }

    context "with @mention routing" do
      let(:agent_channel) { create(:agent_channel, agent: agent1, channel: slack_channel, external_bot_user_id: "U123456") }
      let(:message) { double(content: "<@U123456> hello there", metadata: {}) }

      before { agent_channel } # ensure it exists

      it "routes to the mentioned agent" do
        result = subject
        expect(result).to be_success
        expect(result.data[:agent]).to eq(agent1)
      end

      context "when mentioned agent is disabled" do
        before { agent1.update!(enabled: false) }

        it "falls through to next routing method" do
          # Should not find the disabled agent
          result = subject
          expect(result).to be_success
          expect(result.data[:agent]).not_to eq(agent1)
        end
      end
    end

    context "with thread ownership routing" do
      let(:message) { double(content: "continue the conversation", metadata: { "thread_ts" => "1234567890.123" }) }
      let!(:channel_thread) { create(:channel_thread, channel: slack_channel, agent: agent2, external_thread_id: "1234567890.123") }

      it "routes to the thread owner" do
        result = subject
        expect(result).to be_success
        expect(result.data[:agent]).to eq(agent2)
      end

      context "when thread owner is disabled" do
        before { agent2.update!(enabled: false) }

        it "falls through to next routing method" do
          result = subject
          expect(result).to be_success
          expect(result.data[:agent]).not_to eq(agent2)
        end
      end
    end

    context "with default agent channel routing" do
      let(:message) { double(content: "hello", metadata: {}) }
      let!(:default_agent_channel) { create(:agent_channel, agent: agent1, channel: slack_channel, is_default: true) }

      it "routes to the default agent" do
        result = subject
        expect(result).to be_success
        expect(result.data[:agent]).to eq(agent1)
      end
    end

    context "with legacy default routing" do
      let(:message) { double(content: "hello", metadata: {}) }

      before do
        slack_channel.update!(config: { "default_agent_id" => agent1.id })
      end

      it "routes to the legacy default agent" do
        result = subject
        expect(result).to be_success
        expect(result.data[:agent]).to eq(agent1)
      end

      context "when legacy default agent is disabled" do
        before { agent1.update!(enabled: false) }

        it "falls through to fallback" do
          result = subject
          expect(result).to be_success
          expect(result.data[:agent]).not_to eq(agent1)
        end
      end
    end

    context "with fallback routing" do
      let(:message) { double(content: "hello", metadata: {}) }
      let!(:first_enabled_agent) { agent1 } # agent1 created first

      it "routes to first enabled visible agent" do
        result = subject
        expect(result).to be_success
        expect(result.data[:agent]).to eq(first_enabled_agent)
      end
    end

    context "priority ordering" do
      let(:message) {
        double(
          content: "<@U123456> hello there",
          metadata: { "thread_ts" => "1234567890.123" }
        )
      }

      let!(:agent_channel) { create(:agent_channel, agent: agent1, channel: slack_channel, external_bot_user_id: "U123456") }
      let!(:channel_thread) { create(:channel_thread, channel: slack_channel, agent: agent2, external_thread_id: "1234567890.123") }
      let!(:default_agent_channel) { create(:agent_channel, agent: disabled_agent, channel: slack_channel, is_default: true) }

      it "@mention takes priority over thread ownership" do
        result = subject
        expect(result).to be_success
        expect(result.data[:agent]).to eq(agent1) # mentioned agent wins
      end
    end

    context "error handling" do
      let(:message) { double(content: "hello") }

      before do
        allow_any_instance_of(described_class).to receive(:route_agent).and_raise(StandardError, "test error")
      end

      it "returns failure with error message" do
        result = subject
        expect(result).not_to be_success
        expect(result.error).to include("MessageRouter failed: test error")
      end
    end
  end

  describe "private methods" do
    let(:router) { described_class.new(channel: slack_channel, message: message) }

    describe "#extract_mentioned_bot_id" do
      context "with valid bot mention" do
        let(:message) { double(content: "Hey <@U123456> can you help?") }

        it "extracts the bot user ID" do
          expect(router.send(:extract_mentioned_bot_id)).to eq("U123456")
        end
      end

      context "with no mention" do
        let(:message) { double(content: "Hello world") }

        it "returns nil" do
          expect(router.send(:extract_mentioned_bot_id)).to be_nil
        end
      end
    end
  end
end
