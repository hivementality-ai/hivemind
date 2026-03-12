# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::DmPolicyChecker do
  let(:channel) { create(:channel, :slack) }
  let(:agent) { create(:agent) }
  let(:agent_channel) { create(:agent_channel, agent: agent, channel: channel, dm_policy: policy) }

  describe ".call" do
    context "with open mode" do
      let(:policy) { { "mode" => "open" } }

      it "allows all senders" do
        result = described_class.call(agent_channel: agent_channel, sender: "anyone@example.com")
        expect(result.success?).to be true
        expect(result.data[:allowed]).to be true
      end
    end

    context "with allowlist mode" do
      let(:policy) { { "mode" => "allowlist", "allowed_senders" => [ "+15551234567" ] } }

      it "allows listed senders" do
        result = described_class.call(agent_channel: agent_channel, sender: "+15551234567")
        expect(result.data[:allowed]).to be true
      end

      it "blocks unlisted senders" do
        result = described_class.call(agent_channel: agent_channel, sender: "+19999999999")
        expect(result.data[:allowed]).to be false
      end
    end

    context "with blocklist mode" do
      let(:policy) { { "mode" => "blocklist", "blocked_senders" => [ "spam@example.com" ] } }

      it "blocks listed senders" do
        result = described_class.call(agent_channel: agent_channel, sender: "spam@example.com")
        expect(result.data[:allowed]).to be false
      end

      it "allows unlisted senders" do
        result = described_class.call(agent_channel: agent_channel, sender: "good@example.com")
        expect(result.data[:allowed]).to be true
      end
    end

    context "with require_mention" do
      let(:policy) { { "mode" => "open", "require_mention" => true } }

      it "blocks messages without mention" do
        result = described_class.call(agent_channel: agent_channel, sender: "user@example.com", is_mention: false)
        expect(result.data[:allowed]).to be false
      end

      it "allows messages with mention" do
        result = described_class.call(agent_channel: agent_channel, sender: "user@example.com", is_mention: true)
        expect(result.data[:allowed]).to be true
      end
    end
  end
end
