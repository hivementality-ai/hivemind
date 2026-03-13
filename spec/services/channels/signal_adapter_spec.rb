# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::SignalAdapter do
  let(:channel) do
    create(:channel, :signal, config: {
      "api_url" => "http://signal-cli:8080",
      "phone_number" => "+12175551234"
    })
  end
  let(:adapter) { described_class.new(channel) }

  describe "#receive" do
    context "with a text message" do
      let(:payload) do
        {
          envelope: {
            source: "+19175559876",
            sourceName: "Alice",
            dataMessage: { message: "Hello from Signal!", timestamp: 1707900000 }
          }
        }
      end

      it "creates an inbound message" do
        result = adapter.receive(payload)
        expect(result).to be_success
        expect(result.data[:inbound_message]).to be_a(InboundMessage)
        expect(result.data[:inbound_message].content).to eq("Hello from Signal!")
        expect(result.data[:inbound_message].sender).to eq("+19175559876")
      end

      it "stores source metadata" do
        result = adapter.receive(payload)
        metadata = result.data[:inbound_message].metadata
        expect(metadata["source_name"]).to eq("Alice")
        expect(metadata["timestamp"]).to eq(1707900000)
      end
    end

    context "with a group message" do
      let(:payload) do
        {
          envelope: {
            source: "+19175559876", sourceName: "Alice",
            dataMessage: { message: "Group hello", timestamp: 1707900001, groupInfo: { groupId: "group123" } }
          }
        }
      end

      it "stores group_id in metadata" do
        result = adapter.receive(payload)
        metadata = result.data[:inbound_message].metadata
        expect(metadata["group_id"]).to eq("group123")
      end
    end

    context "with attachments" do
      let(:payload) do
        {
          envelope: {
            source: "+19175559876", sourceName: "Alice",
            dataMessage: {
              message: "See attached", timestamp: 1707900002,
              attachments: [ { contentType: "image/png", filename: "photo.png", size: 12345 } ]
            }
          }
        }
      end

      it "stores attachment info in metadata" do
        result = adapter.receive(payload)
        metadata = result.data[:inbound_message].metadata
        expect(metadata["attachments"]).to be_an(Array)
        expect(metadata["attachments"].first["content_type"]).to eq("image/png")
        expect(metadata["attachments"].first["filename"]).to eq("photo.png")
      end
    end

    context "with a quoted reply" do
      let(:payload) do
        {
          envelope: {
            source: "+19175559876", sourceName: "Alice",
            dataMessage: {
              message: "Replying here", timestamp: 1707900003,
              quote: { id: 1707899000, author: "+12175551234", text: "Original message" }
            }
          }
        }
      end

      it "stores quote in metadata" do
        result = adapter.receive(payload)
        metadata = result.data[:inbound_message].metadata
        expect(metadata["quote"]).to be_present
        expect(metadata["quote"]["author"]).to eq("+12175551234")
      end
    end

    context "without a data message" do
      it "skips non-data updates" do
        result = adapter.receive({ envelope: { source: "+1234" } })
        expect(result).to be_success
        expect(result.data[:skipped]).to be true
      end
    end

    context "when an error occurs" do
      before { allow(adapter).to receive(:log_inbound_message).and_raise(StandardError, "DB error") }

      it "returns failure" do
        payload = { envelope: { source: "+1234", sourceName: "Test", dataMessage: { message: "test", timestamp: 1 } } }
        result = adapter.receive(payload)
        expect(result).not_to be_success
        expect(result.error).to include("Signal receive failed")
      end
    end
  end

  describe "#send_message" do
    context "with text content" do
      it "sends a message via signal-cli REST API" do
        stub_request(:post, "http://signal-cli:8080/v2/send")
          .with(body: hash_including("message" => "Hello from Hivemind!", "number" => "+12175551234", "recipients" => [ "+19175559876" ]))
          .to_return(status: 201, body: { timestamp: 1707900100 }.to_json)

        result = adapter.send_message(to: "+19175559876", content: "Hello from Hivemind!")
        expect(result).to be_success
        expect(result.data[:outbound_message]).to be_a(OutboundMessage)
      end
    end

    context "with quote (reply) options" do
      it "includes quote parameters" do
        stub_request(:post, "http://signal-cli:8080/v2/send")
          .with(body: hash_including("quote_timestamp" => 1707899000, "quote_author" => "+19175559876"))
          .to_return(status: 201, body: { timestamp: 1707900101 }.to_json)

        result = adapter.send_message(to: "+19175559876", content: "Reply!", quote_timestamp: 1707899000, quote_author: "+19175559876")
        expect(result).to be_success
      end
    end

    context "when signal-cli is not running" do
      it "returns failure with connection error" do
        stub_request(:post, "http://signal-cli:8080/v2/send").to_raise(Errno::ECONNREFUSED)
        result = adapter.send_message(to: "+19175559876", content: "Test")
        expect(result).not_to be_success
        expect(result.error).to include("Signal CLI not running")
      end
    end

    context "when signal-cli returns an error" do
      it "returns failure with status code" do
        stub_request(:post, "http://signal-cli:8080/v2/send").to_return(status: 400, body: "Bad request")
        result = adapter.send_message(to: "+19175559876", content: "Test")
        expect(result).not_to be_success
        expect(result.error).to include("Signal API error")
        expect(result.error).to include("400")
      end
    end

    context "when not configured" do
      it "returns failure when phone_number is missing" do
        channel.update(config: { "api_url" => "http://signal-cli:8080" })
        result = adapter.send_message(to: "+19175559876", content: "Test")
        expect(result).not_to be_success
        expect(result.error).to include("Signal not configured")
      end

      it "returns failure when config is empty" do
        channel.update(config: {})
        result = adapter.send_message(to: "+19175559876", content: "Test")
        expect(result).not_to be_success
        expect(result.error).to include("Signal not configured")
      end
    end
  end

  describe "#verify_webhook" do
    it "always returns true" do
      request = double("request")
      expect(adapter.verify_webhook(request)).to be true
    end
  end
end
