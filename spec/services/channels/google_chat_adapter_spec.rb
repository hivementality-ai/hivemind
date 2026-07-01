# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::GoogleChatAdapter do
  let(:channel) { create(:channel, channel_type: "google_chat", config: {}) }
  let(:adapter) { described_class.new(channel) }

  describe "#receive" do
    it "parses a MESSAGE event, replying to the space" do
      payload = {
        type: "MESSAGE",
        message: {
          name: "spaces/AAAA/messages/123",
          text: "hello there",
          sender: { displayName: "Alice", type: "HUMAN" }
        },
        space: { name: "spaces/AAAA" }
      }
      result = adapter.receive(payload)
      expect(result).to be_success
      inbound = result.data[:inbound_message]
      expect(inbound.sender).to eq("spaces/AAAA")
      expect(inbound.content).to eq("hello there")
      expect(inbound.external_id).to eq("spaces/AAAA/messages/123")
      expect(inbound.metadata["sender"]).to eq("Alice")
    end

    it "skips non-MESSAGE events (ADDED_TO_SPACE)" do
      result = adapter.receive({ type: "ADDED_TO_SPACE", space: { name: "spaces/AAAA" } })
      expect(result.data[:skipped]).to be(true)
    end

    it "skips messages from BOT senders" do
      payload = {
        type: "MESSAGE",
        message: { name: "spaces/AAAA/messages/1", text: "echo", sender: { type: "BOT" } },
        space: { name: "spaces/AAAA" }
      }
      result = adapter.receive(payload)
      expect(result.data[:skipped]).to be(true)
    end
  end

  describe "#verify_webhook" do
    it "allows when unconfigured" do
      request = instance_double(ActionDispatch::Request, headers: {})
      expect(adapter.verify_webhook(request)).to be(true)
    end
  end

  describe "#send_message" do
    it "posts a {text:} body to the space's messages endpoint" do
      allow(adapter).to receive(:access_token).and_return("ya29.token")
      stub = stub_request(:post, "https://chat.googleapis.com/v1/spaces/AAAA/messages")
             .with(
               headers: { "Authorization" => "Bearer ya29.token", "Content-Type" => "application/json" },
               body: { text: "hi back" }.to_json
             )
             .to_return(status: 200, body: { name: "spaces/AAAA/messages/999" }.to_json)

      result = adapter.send_message(to: "spaces/AAAA", content: "hi back")
      expect(result).to be_success
      expect(result.data[:outbound_message].recipient).to eq("spaces/AAAA")
      expect(stub).to have_been_requested
    end
  end
end
