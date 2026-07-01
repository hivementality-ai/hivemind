# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::FeishuAdapter do
  let(:channel) do
    create(:channel, channel_type: "feishu", config: { "app_id" => "cli_app", "verification_token" => "vtok" })
  end
  let(:adapter) { described_class.new(channel) }

  def message_event(sender_type: "user", message_type: "text", text: "hello there")
    {
      schema: "2.0",
      header: { event_type: "im.message.receive_v1", token: "vtok" },
      event: {
        sender: { sender_id: { open_id: "ou_123" }, sender_type: sender_type },
        message: {
          message_id: "om_abc",
          chat_id: "oc_chat",
          chat_type: "group",
          message_type: message_type,
          content: { text: text }.to_json
        }
      }
    }
  end

  describe "#receive" do
    it "echoes the challenge for url_verification" do
      result = adapter.receive({ type: "url_verification", challenge: "ch123", token: "vtok" })
      expect(result).to be_success
      expect(result.data[:challenge]).to eq("ch123")
    end

    it "parses an im.message.receive_v1 text event" do
      result = adapter.receive(message_event)
      expect(result).to be_success
      inbound = result.data[:inbound_message]
      expect(inbound.sender).to eq("oc_chat") # reply target is the chat
      expect(inbound.content).to eq("hello there")
      expect(inbound.external_id).to eq("om_abc")
      expect(inbound.metadata["open_id"]).to eq("ou_123")
    end

    it "skips messages from an app/bot sender" do
      result = adapter.receive(message_event(sender_type: "app"))
      expect(result.data[:skipped]).to be(true)
    end

    it "skips non-text message types" do
      result = adapter.receive(message_event(message_type: "audio"))
      expect(result.data[:skipped]).to be(true)
    end

    it "skips blank text" do
      result = adapter.receive(message_event(text: ""))
      expect(result.data[:skipped]).to be(true)
    end
  end

  describe "#verify_webhook" do
    it "allows when no verification token is configured" do
      channel.update!(config: {})
      request = instance_double(ActionDispatch::Request, raw_post: message_event.to_json)
      expect(adapter.verify_webhook(request)).to be(true)
    end

    it "accepts a matching header token" do
      request = instance_double(ActionDispatch::Request, raw_post: message_event.to_json)
      expect(adapter.verify_webhook(request)).to be(true)
    end

    it "rejects a mismatched header token" do
      payload = message_event.tap { |p| p[:header][:token] = "wrong" }
      request = instance_double(ActionDispatch::Request, raw_post: payload.to_json)
      expect(adapter.verify_webhook(request)).to be(false)
    end

    it "accepts a url_verification handshake regardless of token" do
      request = instance_double(ActionDispatch::Request, raw_post: { type: "url_verification", challenge: "x" }.to_json)
      expect(adapter.verify_webhook(request)).to be(true)
    end
  end

  describe "#send_message" do
    before do
      VaultEntry.create!(namespace: "channel_credentials", key: "feishu_app_secret", value: "secret")

      stub_request(:post, "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal")
        .to_return(status: 200, body: { code: 0, tenant_access_token: "t-abc", expire: 7200 }.to_json,
                   headers: { "Content-Type" => "application/json" })
    end

    it "mints a token and posts a text message to the chat" do
      post = stub_request(:post, "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=chat_id")
        .with(
          headers: { "Authorization" => "Bearer t-abc" },
          body: { receive_id: "oc_chat", msg_type: "text", content: { text: "hi" }.to_json }.to_json
        )
        .to_return(status: 200, body: { code: 0, data: { message_id: "om_out" } }.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = adapter.send_message(to: "oc_chat", content: "hi")
      expect(result).to be_success
      expect(result.data[:outbound_message].recipient).to eq("oc_chat")
      expect(post).to have_been_requested
    end

    it "fails when the API returns a non-zero code" do
      stub_request(:post, "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=chat_id")
        .to_return(status: 200, body: { code: 99991663, msg: "token invalid" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = adapter.send_message(to: "oc_chat", content: "hi")
      expect(result).not_to be_success
      expect(result.error).to include("token invalid")
    end
  end
end
