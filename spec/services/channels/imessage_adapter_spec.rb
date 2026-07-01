# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::ImessageAdapter do
  let(:channel) do
    create(:channel, channel_type: "imessage", config: { "server_url" => "http://bluebubbles.test" })
  end
  let(:adapter) { described_class.new(channel) }

  def new_message(text: "hey there", is_from_me: false)
    {
      type: "new-message",
      data: {
        guid: "msg-guid-1",
        text: text,
        isFromMe: is_from_me,
        handle: { address: "+15551234567" },
        chats: [ { guid: "iMessage;-;+15551234567" } ]
      }
    }
  end

  describe "#receive" do
    it "parses a new-message payload, replying to the chat guid" do
      expect { adapter.receive(new_message) }.to change(InboundMessage, :count).by(1)
      inbound = InboundMessage.last
      expect(inbound.sender).to eq("iMessage;-;+15551234567")
      expect(inbound.content).to eq("hey there")
      expect(inbound.external_id).to eq("msg-guid-1")
      expect(inbound.metadata["address"]).to eq("+15551234567")
    end

    it "skips our own outgoing messages (isFromMe)" do
      result = adapter.receive(new_message(is_from_me: true))
      expect(result.data[:skipped]).to be(true)
      expect(InboundMessage.count).to eq(0)
    end

    it "skips blank text" do
      result = adapter.receive(new_message(text: " "))
      expect(result.data[:skipped]).to be(true)
    end

    it "ignores non new-message events" do
      result = adapter.receive({ type: "updated-message", data: {} })
      expect(result.data[:skipped]).to be(true)
    end
  end

  describe "#verify_webhook" do
    it "allows when no secret is configured" do
      request = instance_double(ActionDispatch::Request, query_parameters: {}, params: {})
      expect(adapter.verify_webhook(request)).to be(true)
    end

    context "with a configured webhook secret" do
      let(:channel) do
        create(:channel, channel_type: "imessage",
                         config: { "server_url" => "http://bluebubbles.test", "webhook_secret" => "s3cret" })
      end

      it "accepts a matching ?secret param" do
        request = instance_double(ActionDispatch::Request, query_parameters: { "secret" => "s3cret" }, params: {})
        expect(adapter.verify_webhook(request)).to be(true)
      end

      it "rejects a wrong secret" do
        request = instance_double(ActionDispatch::Request, query_parameters: { "secret" => "nope" }, params: {})
        expect(adapter.verify_webhook(request)).to be(false)
      end
    end
  end

  describe "#send_message" do
    before do
      VaultEntry.create!(namespace: "channel_credentials", key: "bluebubbles_password", encrypted_value: "hunter2")
    end

    it "POSTs the chat guid and message to the BlueBubbles text endpoint" do
      stub = stub_request(:post, %r{http://bluebubbles\.test/api/v1/message/text})
             .with { |req| body = JSON.parse(req.body); body["chatGuid"] == "chat-guid" && body["message"] == "hello" }
             .to_return(status: 200, body: { status: 200, data: { guid: "out-1" } }.to_json,
                        headers: { "Content-Type" => "application/json" })

      result = adapter.send_message(to: "chat-guid", content: "hello")

      expect(result).to be_success
      expect(stub).to have_been_requested
      expect(OutboundMessage.last.recipient).to eq("chat-guid")
    end

    it "fails when the password is not configured" do
      VaultEntry.delete_all
      result = adapter.send_message(to: "chat-guid", content: "hello")
      expect(result).not_to be_success
    end
  end
end
