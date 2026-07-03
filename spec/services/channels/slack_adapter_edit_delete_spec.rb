# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::SlackAdapter do
  let(:channel) { create(:channel, :slack) }
  let(:adapter) { described_class.new(channel) }
  let(:slack_token) { "xoxb-test-token-edit" }
  let(:channel_id) { "C987654" }
  let(:message_ts) { "1609459200.000001" }

  before do
    create(:vault_entry, namespace: "channel_credentials", key: "slack_bot_token", value: slack_token)
  end

  describe "#edit_message" do
    it "calls chat.update with correct channel, ts, and text" do
      stub = stub_request(:post, "https://slack.com/api/chat.update")
        .with(
          headers: { "Authorization" => "Bearer #{slack_token}" },
          body: hash_including(
            "channel" => channel_id,
            "ts" => message_ts,
            "text" => "Edited content"
          )
        )
        .to_return(status: 200, body: { ok: true, ts: message_ts, channel: channel_id }.to_json)

      result = adapter.edit_message(message_ts, "Edited content", channel_id: channel_id)

      expect(result).to be_success
      expect(stub).to have_been_requested
    end

    it "returns failure when Slack returns an error" do
      stub_request(:post, "https://slack.com/api/chat.update")
        .to_return(status: 200, body: { ok: false, error: "cant_update_message" }.to_json)

      result = adapter.edit_message(message_ts, "Edited content", channel_id: channel_id)

      expect(result).not_to be_success
      expect(result.error).to include("cant_update_message")
    end
  end

  describe "#delete_message" do
    it "calls chat.delete with correct channel and ts" do
      stub = stub_request(:post, "https://slack.com/api/chat.delete")
        .with(
          headers: { "Authorization" => "Bearer #{slack_token}" },
          body: hash_including(
            "channel" => channel_id,
            "ts" => message_ts
          )
        )
        .to_return(status: 200, body: { ok: true }.to_json)

      result = adapter.delete_message(message_ts, channel_id: channel_id)

      expect(result).to be_success
      expect(stub).to have_been_requested
    end

    it "returns failure when Slack returns an error" do
      stub_request(:post, "https://slack.com/api/chat.delete")
        .to_return(status: 200, body: { ok: false, error: "message_not_found" }.to_json)

      result = adapter.delete_message(message_ts, channel_id: channel_id)

      expect(result).not_to be_success
      expect(result.error).to include("message_not_found")
    end
  end

  describe "#send_message records platform_message_id" do
    it "stores the Slack ts as platform_message_id on the OutboundMessage" do
      stub_request(:post, "https://slack.com/api/chat.postMessage")
        .to_return(
          status: 200,
          body: { ok: true, ts: message_ts, channel: channel_id }.to_json
        )

      result = adapter.send_message(to: channel_id, content: "Hello Slack")

      expect(result).to be_success
      outbound = result.data[:outbound_message]
      expect(outbound.platform_message_id).to eq(message_ts)
    end
  end
end
