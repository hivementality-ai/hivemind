# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::TelegramAdapter do
  let(:channel) { create(:channel, :telegram) }
  let(:adapter) { described_class.new(channel) }
  let(:bot_token) { "123456:ABC-DEF-test-token" }

  before do
    create(:vault_entry, namespace: "channel_credentials", key: "telegram_bot_token", value: bot_token)
  end

  describe "#receive" do
    context "with a text message" do
      let(:payload) do
        {
          message: {
            message_id: 42,
            from: { id: 12345, first_name: "Test", username: "testuser" },
            chat: { id: 67890, type: "private" },
            text: "Hello bot!",
            date: 1707900000
          }
        }
      end

      it "creates an inbound message" do
        result = adapter.receive(payload)
        expect(result).to be_success
        expect(result.data[:inbound_message]).to be_a(InboundMessage)
        expect(result.data[:inbound_message].content).to eq("Hello bot!")
        expect(result.data[:inbound_message].sender).to eq("12345")
        expect(result.data[:inbound_message].external_id).to eq("42")
      end

      it "stores chat metadata" do
        result = adapter.receive(payload)
        metadata = result.data[:inbound_message].metadata
        expect(metadata["chat_id"]).to eq(67890)
        expect(metadata["chat_type"]).to eq("private")
      end
    end

    context "with a photo message" do
      let(:payload) do
        {
          message: {
            message_id: 43,
            from: { id: 12345, first_name: "Test" },
            chat: { id: 67890, type: "private" },
            photo: [
              { file_id: "small_id", file_size: 1000 },
              { file_id: "large_id", file_size: 50000 }
            ],
            caption: "Check this out",
            date: 1707900000
          }
        }
      end

      it "extracts caption as content" do
        result = adapter.receive(payload)
        expect(result).to be_success
        expect(result.data[:inbound_message].content).to eq("Check this out")
      end

      it "stores the largest photo file_id in metadata" do
        result = adapter.receive(payload)
        metadata = result.data[:inbound_message].metadata
        expect(metadata["photo_file_id"]).to eq("large_id")
        expect(metadata["has_photo"]).to be true
      end
    end

    context "with an edited message" do
      let(:payload) do
        {
          edited_message: {
            message_id: 44,
            from: { id: 12345, first_name: "Test" },
            chat: { id: 67890, type: "private" },
            text: "Edited text",
            date: 1707900000
          }
        }
      end

      it "processes edited messages" do
        result = adapter.receive(payload)
        expect(result).to be_success
        expect(result.data[:inbound_message].content).to eq("Edited text")
      end
    end

    context "with a reply message" do
      let(:payload) do
        {
          message: {
            message_id: 45,
            from: { id: 12345, first_name: "Test" },
            chat: { id: 67890, type: "private" },
            text: "This is a reply",
            reply_to_message: { message_id: 40 },
            date: 1707900000
          }
        }
      end

      it "stores reply_to_message_id in metadata" do
        result = adapter.receive(payload)
        metadata = result.data[:inbound_message].metadata
        expect(metadata["reply_to_message_id"]).to eq(40)
      end
    end

    context "with no message" do
      it "skips non-message updates" do
        result = adapter.receive({ update_id: 123 })
        expect(result).to be_success
        expect(result.data[:skipped]).to be true
      end
    end

    context "when an error occurs" do
      before do
        allow(adapter).to receive(:log_inbound_message).and_raise(StandardError, "DB error")
      end

      it "returns failure" do
        payload = {
          message: {
            message_id: 1, from: { id: 1 }, chat: { id: 1, type: "private" },
            text: "test", date: 1
          }
        }
        result = adapter.receive(payload)
        expect(result).not_to be_success
        expect(result.error).to include("Telegram receive failed")
      end
    end
  end

  describe "#send_message" do
    context "with text content" do
      it "sends a message via sendMessage API" do
        stub_request(:post, "https://api.telegram.org/bot#{bot_token}/sendMessage")
          .with(body: hash_including("chat_id" => "67890", "text" => "Hello from Hivemind!", "parse_mode" => "Markdown"))
          .to_return(status: 200, body: { ok: true, result: { message_id: 100 } }.to_json)

        result = adapter.send_message(to: "67890", content: "Hello from Hivemind!")
        expect(result).to be_success
        expect(result.data[:outbound_message]).to be_a(OutboundMessage)
        expect(result.data[:response]["message_id"]).to eq(100)
      end
    end

    context "with reply_to option" do
      it "includes reply_to_message_id" do
        stub_request(:post, "https://api.telegram.org/bot#{bot_token}/sendMessage")
          .with(body: hash_including("reply_to_message_id" => 42))
          .to_return(status: 200, body: { ok: true, result: { message_id: 101 } }.to_json)

        result = adapter.send_message(to: "67890", content: "Reply!", reply_to: 42)
        expect(result).to be_success
      end
    end

    context "with silent option" do
      it "disables notification" do
        stub_request(:post, "https://api.telegram.org/bot#{bot_token}/sendMessage")
          .with(body: hash_including("disable_notification" => true))
          .to_return(status: 200, body: { ok: true, result: { message_id: 102 } }.to_json)

        result = adapter.send_message(to: "67890", content: "Shh!", silent: true)
        expect(result).to be_success
      end
    end

    context "with photo_url" do
      it "sends a photo via sendPhoto API" do
        stub_request(:post, "https://api.telegram.org/bot#{bot_token}/sendPhoto")
          .with(body: hash_including("chat_id" => "67890", "photo" => "https://example.com/image.jpg", "caption" => "Nice picture"))
          .to_return(status: 200, body: { ok: true, result: { message_id: 103 } }.to_json)

        result = adapter.send_message(to: "67890", content: "Nice picture", photo_url: "https://example.com/image.jpg")
        expect(result).to be_success
        expect(result.data[:outbound_message].metadata["type"]).to eq("photo")
      end
    end

    context "when bot token is not configured" do
      before { VaultEntry.where(namespace: "channel_credentials", key: "telegram_bot_token").destroy_all }

      it "returns failure" do
        result = adapter.send_message(to: "67890", content: "Test")
        expect(result).not_to be_success
        expect(result.error).to include("bot token not configured")
      end
    end

    context "when Telegram API returns an error" do
      it "returns failure with description" do
        stub_request(:post, "https://api.telegram.org/bot#{bot_token}/sendMessage")
          .to_return(status: 200, body: { ok: false, description: "Bad Request: chat not found" }.to_json)

        result = adapter.send_message(to: "invalid", content: "Test")
        expect(result).not_to be_success
        expect(result.error).to include("chat not found")
      end
    end
  end

  describe "#react" do
    it "sets a reaction on a message" do
      stub_request(:post, "https://api.telegram.org/bot#{bot_token}/setMessageReaction")
        .with(body: hash_including("chat_id" => "67890", "message_id" => 42))
        .to_return(status: 200, body: { ok: true }.to_json)

      result = adapter.react(message_id: 42, emoji: "thumbsup", chat_id: "67890")
      expect(result).to be_success
    end

    it "uses default_chat_id from config when chat_id not provided" do
      channel.update(config: { "default_chat_id" => "99999" })
      stub_request(:post, "https://api.telegram.org/bot#{bot_token}/setMessageReaction")
        .with(body: hash_including("chat_id" => "99999"))
        .to_return(status: 200, body: { ok: true }.to_json)

      result = adapter.react(message_id: 42, emoji: "heart")
      expect(result).to be_success
    end

    it "returns failure when no chat_id available" do
      channel.update(config: {})
      result = adapter.react(message_id: 42, emoji: "heart")
      expect(result).not_to be_success
      expect(result.error).to include("No chat_id")
    end
  end

  describe "#verify_webhook" do
    context "with no secret configured" do
      it "returns true (dev mode)" do
        channel.update(config: {})
        request = double("request")
        expect(adapter.verify_webhook(request)).to be true
      end
    end

    context "with secret configured" do
      before { channel.update(config: { "webhook_secret" => "my-secret-token" }) }

      it "accepts valid secret token header" do
        request = double("request", headers: { "X-Telegram-Bot-Api-Secret-Token" => "my-secret-token" })
        expect(adapter.verify_webhook(request)).to be true
      end

      it "rejects invalid secret token header" do
        request = double("request", headers: { "X-Telegram-Bot-Api-Secret-Token" => "wrong-token" })
        expect(adapter.verify_webhook(request)).to be false
      end

      it "rejects missing secret token header" do
        request = double("request", headers: {})
        expect(adapter.verify_webhook(request)).to be false
      end
    end
  end
end
