# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::EmailAdapter do
  let(:channel) do
    create(:channel, channel_type: "email", config: { "from_email" => "agent@hive.test" })
  end
  let(:adapter) { described_class.new(channel) }

  describe "#receive" do
    it "parses provider inbound-parse fields and extracts the sender address" do
      payload = {
        from: "Alice <alice@example.com>",
        subject: "Need help",
        text: "Can you check the report?",
        "message-id": "<abc@example.com>"
      }
      result = adapter.receive(payload)
      expect(result).to be_success
      inbound = result.data[:inbound_message]
      expect(inbound.sender).to eq("alice@example.com")
      expect(inbound.content).to include("Subject: Need help").and include("check the report")
      expect(inbound.metadata["subject"]).to eq("Need help")
    end

    it "skips payloads with no sender" do
      result = adapter.receive({ subject: "x", text: "y" })
      expect(result.data[:skipped]).to be(true)
    end
  end

  describe "#send_message" do
    it "delivers an email reply from the configured address" do
      expect {
        result = adapter.send_message(to: "alice@example.com", content: "Here you go.")
        expect(result).to be_success
      }.to change { ActionMailer::Base.deliveries.size }.by(1)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ "alice@example.com" ])
      expect(mail.from).to eq([ "agent@hive.test" ])
      expect(mail.body.to_s).to include("Here you go.")
    end
  end

  describe "#verify_webhook" do
    it "allows when no secret is configured" do
      request = instance_double(ActionDispatch::Request, query_parameters: {}, headers: {})
      expect(adapter.verify_webhook(request)).to be(true)
    end
  end
end
