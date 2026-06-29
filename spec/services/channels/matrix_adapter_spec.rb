# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::MatrixAdapter do
  let(:channel) do
    create(:channel, channel_type: "matrix", config: {
      "homeserver_url" => "https://matrix.example.org",
      "user_id" => "@hivemind:example.org",
      "hs_token" => "secret-hs-token"
    })
  end
  let(:adapter) { described_class.new(channel) }

  describe "#receive" do
    let(:payload) do
      {
        events: [
          {
            type: "m.room.message",
            room_id: "!room:example.org",
            sender: "@alice:example.org",
            event_id: "$evt1",
            content: { msgtype: "m.text", body: "hello matrix" }
          }
        ]
      }
    end

    it "creates an inbound message per text event and routes the reply to the room" do
      expect { adapter.receive(payload) }.to change(InboundMessage, :count).by(1)
      inbound = InboundMessage.last
      expect(inbound.content).to eq("hello matrix")
      expect(inbound.sender).to eq("!room:example.org")
      expect(inbound.metadata["matrix_user"]).to eq("@alice:example.org")
    end

    it "ignores the bot's own messages" do
      payload[:events][0][:sender] = "@hivemind:example.org"
      expect { adapter.receive(payload) }.not_to change(InboundMessage, :count)
    end

    it "is idempotent across transaction retries (unique event_id)" do
      adapter.receive(payload)
      expect { adapter.receive(payload) }.not_to change(InboundMessage, :count)
    end
  end

  describe "#verify_webhook" do
    it "accepts the matching hs_token via query param" do
      request = instance_double(ActionDispatch::Request, query_parameters: { "access_token" => "secret-hs-token" }, headers: {})
      expect(adapter.verify_webhook(request)).to be(true)
    end

    it "rejects a wrong token" do
      request = instance_double(ActionDispatch::Request, query_parameters: { "access_token" => "nope" }, headers: {})
      expect(adapter.verify_webhook(request)).to be(false)
    end
  end
end
