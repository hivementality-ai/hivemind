# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::MsteamsAdapter do
  let(:channel) do
    create(:channel, channel_type: "msteams", config: { "app_id" => "app-123" })
  end
  let(:adapter) { described_class.new(channel) }

  describe "#receive" do
    it "parses a Bot Framework message Activity, encoding the reply target and stripping mentions" do
      payload = {
        type: "message",
        id: "activity-1",
        text: "<at>Hivemind</at> hello there",
        from: { id: "user-9", name: "Alice" },
        conversation: { id: "conv-7" },
        serviceUrl: "https://smba.example.com/",
        channelId: "msteams"
      }

      result = adapter.receive(payload)
      expect(result).to be_success

      inbound = result.data[:inbound_message]
      expect(inbound.sender).to eq("https://smba.example.com/|conv-7")
      expect(inbound.content).to eq("hello there")
      expect(inbound.external_id).to eq("activity-1")
      expect(inbound.metadata["from_name"]).to eq("Alice")
      expect(inbound.metadata["conversation_id"]).to eq("conv-7")
    end

    it "skips non-message activities" do
      result = adapter.receive({ type: "conversationUpdate", id: "x" })
      expect(result.data[:skipped]).to be(true)
    end

    it "skips messages with blank text" do
      result = adapter.receive({ type: "message", id: "x", text: "<at>bot</at>", conversation: { id: "c" } })
      expect(result.data[:skipped]).to be(true)
    end
  end

  describe "#verify_webhook" do
    it "allows when app_id is not configured" do
      channel.update!(config: {})
      request = instance_double(ActionDispatch::Request, headers: {})
      expect(adapter.verify_webhook(request)).to be(true)
    end

    it "requires a Bearer header when app_id is configured" do
      with_bearer = instance_double(ActionDispatch::Request, headers: { "Authorization" => "Bearer jwt" })
      without_bearer = instance_double(ActionDispatch::Request, headers: {})
      expect(adapter.verify_webhook(with_bearer)).to be(true)
      expect(adapter.verify_webhook(without_bearer)).to be(false)
    end
  end

  describe "#send_message" do
    before do
      VaultEntry.create!(namespace: "channel_credentials", key: "msteams_app_password", value: "secret-pw")

      stub_request(:post, Channels::MsteamsAdapter::TOKEN_URL)
        .to_return(status: 200, body: { access_token: "aad-token", expires_in: 3600 }.to_json,
                   headers: { "Content-Type" => "application/json" })
    end

    it "splits the reply target and posts the activity to the conversation URL" do
      stub = stub_request(:post, "https://smba.example.com/v3/conversations/conv-7/activities")
        .with(
          headers: { "Authorization" => "Bearer aad-token", "Content-Type" => "application/json" },
          body: { type: "message", text: "hi back" }.to_json
        )
        .to_return(status: 200, body: { id: "reply-1" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = adapter.send_message(to: "https://smba.example.com/|conv-7", content: "hi back")

      expect(result).to be_success
      expect(stub).to have_been_requested
      expect(result.data[:outbound_message].recipient).to eq("https://smba.example.com/|conv-7")
    end

    it "returns failure when the API response has no activity id" do
      stub_request(:post, "https://smba.example.com/v3/conversations/conv-7/activities")
        .to_return(status: 502, body: { error: "bad gateway" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = adapter.send_message(to: "https://smba.example.com/|conv-7", content: "hi")
      expect(result).not_to be_success
    end
  end
end
