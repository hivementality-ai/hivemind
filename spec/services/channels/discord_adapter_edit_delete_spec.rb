# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::DiscordAdapter do
  let(:channel) { create(:channel, :discord) }
  let(:adapter) { described_class.new(channel) }
  let(:bot_token) { "Bot-test-token" }
  let(:channel_id) { "111222333" }
  let(:message_id) { "999888777" }

  before do
    create(:vault_entry, namespace: "channel_credentials", key: "discord_bot_token", value: bot_token)
  end

  describe "#edit_message" do
    it "sends PATCH to the correct URL with the new content" do
      stub = stub_request(:patch, "https://discord.com/api/v10/channels/#{channel_id}/messages/#{message_id}")
        .with(
          headers: { "Authorization" => "Bot #{bot_token}" },
          body: hash_including("content" => "Updated text")
        )
        .to_return(
          status: 200,
          body: { id: message_id, content: "Updated text" }.to_json
        )

      result = adapter.edit_message(message_id, "Updated text", channel_id: channel_id)

      expect(result).to be_success
      expect(stub).to have_been_requested
    end

    it "returns failure when Discord returns an error" do
      stub_request(:patch, "https://discord.com/api/v10/channels/#{channel_id}/messages/#{message_id}")
        .to_return(status: 403, body: { message: "Missing Permissions" }.to_json)

      result = adapter.edit_message(message_id, "Updated text", channel_id: channel_id)

      expect(result).not_to be_success
      expect(result.error).to include("403")
    end
  end

  describe "#delete_message" do
    it "sends DELETE to the correct URL" do
      stub = stub_request(:delete, "https://discord.com/api/v10/channels/#{channel_id}/messages/#{message_id}")
        .with(headers: { "Authorization" => "Bot #{bot_token}" })
        .to_return(status: 204, body: "")

      result = adapter.delete_message(message_id, channel_id: channel_id)

      expect(result).to be_success
      expect(stub).to have_been_requested
    end

    it "returns failure when Discord returns an error" do
      stub_request(:delete, "https://discord.com/api/v10/channels/#{channel_id}/messages/#{message_id}")
        .to_return(status: 404, body: { message: "Unknown Message" }.to_json)

      result = adapter.delete_message(message_id, channel_id: channel_id)

      expect(result).not_to be_success
      expect(result.error).to include("404")
    end
  end

  describe "#send_message records platform_message_id" do
    it "stores the Discord message id as platform_message_id on the OutboundMessage" do
      stub_request(:post, "https://discord.com/api/v10/channels/#{channel_id}/messages")
        .to_return(
          status: 200,
          body: { id: "555444333", content: "Hello" }.to_json
        )

      result = adapter.send_message(to: channel_id, content: "Hello")

      expect(result).to be_success
      outbound = result.data[:outbound_message]
      expect(outbound.platform_message_id).to eq("555444333")
    end
  end
end
