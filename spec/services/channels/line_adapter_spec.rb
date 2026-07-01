# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::LineAdapter do
  let(:channel) { create(:channel, channel_type: "line", config: {}) }
  let(:adapter) { described_class.new(channel) }

  describe "#receive" do
    let(:payload) do
      {
        events: [
          {
            type: "message",
            replyToken: "rt1",
            source: { type: "group", userId: "U123", groupId: "G456" },
            message: { id: "msg1", type: "text", text: "hello line" }
          }
        ]
      }
    end

    it "creates an inbound message per text event and routes the reply to the group" do
      expect { adapter.receive(payload) }.to change(InboundMessage, :count).by(1)
      inbound = InboundMessage.last
      expect(inbound.content).to eq("hello line")
      expect(inbound.sender).to eq("G456")
      expect(inbound.external_id).to eq("msg1")
      expect(inbound.metadata["line_user"]).to eq("U123")
    end

    it "enqueues an InboundMessageJob for the message" do
      expect { adapter.receive(payload) }.to have_enqueued_job(InboundMessageJob)
    end

    it "falls back to the userId when there is no group or room" do
      payload[:events][0][:source] = { type: "user", userId: "U123" }
      adapter.receive(payload)
      expect(InboundMessage.last.sender).to eq("U123")
    end

    it "skips non-message events" do
      payload[:events][0][:type] = "follow"
      expect { adapter.receive(payload) }.not_to change(InboundMessage, :count)
    end

    it "is idempotent across webhook retries (unique external_id)" do
      adapter.receive(payload)
      expect { adapter.receive(payload) }.not_to change(InboundMessage, :count)
    end
  end

  describe "#verify_webhook" do
    let(:raw_post) { '{"events":[]}' }
    let(:request) { instance_double(ActionDispatch::Request, raw_post: raw_post, headers: headers) }
    let(:headers) { {} }

    it "allows when no channel secret is configured" do
      expect(adapter.verify_webhook(request)).to be(true)
    end

    context "with a configured channel secret" do
      let(:secret) { "line-secret" }
      let(:signature) { Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, raw_post)) }

      before do
        create(:vault_entry, namespace: "channel_credentials", key: "line_channel_secret", value: secret)
      end

      it "accepts a correct signature" do
        allow(request).to receive(:headers).and_return("X-Line-Signature" => signature)
        expect(adapter.verify_webhook(request)).to be(true)
      end

      it "rejects a wrong signature" do
        allow(request).to receive(:headers).and_return("X-Line-Signature" => "bogus")
        expect(adapter.verify_webhook(request)).to be(false)
      end
    end
  end

  describe "#send_message" do
    before do
      create(:vault_entry, namespace: "channel_credentials", key: "line_channel_access_token", value: "tok")
    end

    it "posts the correct push body and logs the outbound message" do
      stub = stub_request(:post, "https://api.line.me/v2/bot/message/push")
        .with(
          headers: { "Authorization" => "Bearer tok", "Content-Type" => "application/json" },
          body: { to: "G456", messages: [ { type: "text", text: "hi there" } ] }.to_json
        )
        .to_return(status: 200, body: "{}")

      result = adapter.send_message(to: "G456", content: "hi there")

      expect(result).to be_success
      expect(stub).to have_been_requested
      expect(OutboundMessage.last.recipient).to eq("G456")
    end

    it "returns failure on a non-200 response" do
      stub_request(:post, "https://api.line.me/v2/bot/message/push")
        .to_return(status: 400, body: '{"message":"bad"}')

      result = adapter.send_message(to: "G456", content: "hi")
      expect(result).not_to be_success
    end

    it "returns failure when no access token is configured" do
      VaultEntry.delete_all
      result = adapter.send_message(to: "G456", content: "hi")
      expect(result).not_to be_success
    end
  end
end
