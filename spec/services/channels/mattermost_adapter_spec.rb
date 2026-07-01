# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::MattermostAdapter do
  let(:channel) do
    create(:channel, channel_type: "mattermost",
      config: { "base_url" => "https://mm.test", "outgoing_token" => "out-tok" })
  end
  let(:adapter) { described_class.new(channel) }

  let(:payload) do
    {
      token: "out-tok",
      team_id: "team1",
      channel_id: "chan1",
      channel_name: "town-square",
      user_id: "user1",
      user_name: "alice",
      post_id: "post1",
      text: "hey bot"
    }
  end

  describe "#receive" do
    it "parses an outgoing-webhook payload, replying to the channel" do
      result = adapter.receive(payload)
      expect(result).to be_success
      inbound = result.data[:inbound_message]
      expect(inbound.sender).to eq("chan1")
      expect(inbound.content).to eq("hey bot")
      expect(inbound.external_id).to eq("post1")
      expect(inbound.metadata["user_name"]).to eq("alice")
    end

    it "skips blank text" do
      result = adapter.receive(payload.merge(text: ""))
      expect(result.data[:skipped]).to be(true)
    end

    it "skips the bot's own messages" do
      channel.update!(config: channel.config.merge("bot_user_id" => "user1"))
      result = adapter.receive(payload)
      expect(result.data[:skipped]).to be(true)
    end
  end

  describe "#send_message" do
    before do
      allow(VaultEntry).to receive(:find_by)
        .with(namespace: "channel_credentials", key: "mattermost_bot_token")
        .and_return(double(value: "bot-token"))
    end

    it "POSTs to the v4 API and logs the outbound message" do
      stub = stub_request(:post, "https://mm.test/api/v4/posts")
        .with(
          headers: { "Authorization" => "Bearer bot-token" },
          body: { channel_id: "chan1", message: "hi there" }.to_json
        )
        .to_return(status: 201, body: { id: "newpost" }.to_json)

      result = adapter.send_message(to: "chan1", content: "hi there")
      expect(result).to be_success
      expect(result.data[:outbound_message].recipient).to eq("chan1")
      expect(stub).to have_been_requested
    end

    it "fails when the bot token is not configured" do
      allow(VaultEntry).to receive(:find_by)
        .with(namespace: "channel_credentials", key: "mattermost_bot_token")
        .and_return(nil)

      result = adapter.send_message(to: "chan1", content: "hi")
      expect(result).not_to be_success
    end
  end

  describe "#verify_webhook" do
    it "allows when no token is configured" do
      channel.update!(config: { "base_url" => "https://mm.test" })
      request = instance_double(ActionDispatch::Request, params: {}, request_parameters: {})
      expect(adapter.verify_webhook(request)).to be(true)
    end

    it "validates the token when configured" do
      good = instance_double(ActionDispatch::Request, params: { "token" => "out-tok" }, request_parameters: {})
      bad  = instance_double(ActionDispatch::Request, params: { "token" => "nope" }, request_parameters: {})
      expect(adapter.verify_webhook(good)).to be(true)
      expect(adapter.verify_webhook(bad)).to be(false)
    end
  end
end
