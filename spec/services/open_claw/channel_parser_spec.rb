# frozen_string_literal: true

require "rails_helper"

RSpec.describe OpenClaw::ChannelParser do
  let(:agent) { create(:agent) }

  after { cleanup_openclaw_workspace(@workspace_path) if @workspace_path }

  describe ".call" do
    context "with valid channels" do
      before do
        @workspace_path = create_openclaw_workspace(
          config: {
            "channels" => [
              { "type" => "slack", "name" => "Work Slack", "config" => { "channel_id" => "C123", "bot_token" => "xoxb-secret" } },
              { "type" => "discord", "name" => "Gaming Discord", "config" => { "guild_id" => "G456", "bot_token" => "discord-secret" } }
            ],
            "tools" => []
          }
        )
      end

      it "creates channels with enabled: false" do
        result = described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(result).to be_success
        expect(result.data[:created].size).to eq(2)

        channels = Channel.where(name: ["Work Slack", "Gaming Discord"])
        expect(channels.pluck(:enabled)).to all(be false)
      end

      it "sanitizes credential keys from config" do
        described_class.call(workspace_path: @workspace_path, agent: agent)

        slack = Channel.find_by(name: "Work Slack")
        expect(slack.config).to have_key("channel_id")
        expect(slack.config).not_to have_key("bot_token")
      end

      it "creates AgentChannel join records" do
        described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(AgentChannel.where(agent: agent).count).to eq(2)
      end
    end

    context "with unsupported channel types" do
      before do
        @workspace_path = create_openclaw_workspace(
          config: {
            "channels" => [
              { "type" => "irc", "name" => "Old IRC" }
            ],
            "tools" => []
          }
        )
      end

      it "skips unsupported types" do
        result = described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(result).to be_success
        expect(result.data[:created]).to be_empty
        expect(result.data[:skipped].size).to eq(1)
        expect(result.data[:skipped].first[:reason]).to match(/Unsupported/)
      end
    end

    context "with nested secret keys in config" do
      before do
        @workspace_path = create_openclaw_workspace(
          config: {
            "channels" => [
              {
                "type" => "slack", "name" => "Deep Secrets",
                "config" => {
                  "workspace" => "acme",
                  "auth" => { "api_key" => "sk-123", "scope" => "chat:write" }
                }
              }
            ],
            "tools" => []
          }
        )
      end

      it "deep-strips credential keys" do
        described_class.call(workspace_path: @workspace_path, agent: agent)

        channel = Channel.find_by(name: "Deep Secrets")
        expect(channel.config["workspace"]).to eq("acme")
        expect(channel.config.dig("auth", "scope")).to eq("chat:write")
        expect(channel.config.dig("auth", "api_key")).to be_nil
      end
    end

    context "without config.json" do
      before do
        @workspace_path = Dir.mktmpdir("openclaw_test_")
      end

      it "returns empty results" do
        result = described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(result).to be_success
        expect(result.data[:created]).to be_empty
      end
    end

    context "idempotent re-run" do
      before do
        @workspace_path = create_openclaw_workspace(
          config: {
            "channels" => [
              { "type" => "slack", "name" => "Work Slack", "config" => { "channel_id" => "C123" } }
            ],
            "tools" => []
          }
        )
      end

      it "does not create duplicate channels" do
        described_class.call(workspace_path: @workspace_path, agent: agent)
        result = described_class.call(workspace_path: @workspace_path, agent: agent)

        expect(result).to be_success
        expect(Channel.where(name: "Work Slack").count).to eq(1)
        expect(result.data[:skipped].size).to eq(1)
      end
    end
  end
end
