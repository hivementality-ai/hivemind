# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Serializers::ChannelSerializer do
  def build_channel(attrs = {})
    Channel.new({
      name:         "my-channel",
      channel_type: "slack",
      config:       {},
      enabled:      true
    }.merge(attrs))
  end

  describe "#call" do
    it "returns a hash with required fields" do
      channel = build_channel
      result  = described_class.call(channel: channel)

      expect(result["name"]).to eq("my-channel")
      expect(result["type"]).to eq("slack")
    end

    it "derives ref from the channel name" do
      channel = build_channel(name: "My Slack Channel")
      result  = described_class.call(channel: channel)
      expect(result["ref"]).to eq("my-slack-channel")
    end

    it "includes config when present" do
      channel = build_channel(config: { "webhook_url" => "https://hooks.slack.com/xyz" })
      result  = described_class.call(channel: channel)
      expect(result["config"]["webhook_url"]).to eq("https://hooks.slack.com/xyz")
    end

    it "omits config when empty" do
      channel = build_channel(config: {})
      result  = described_class.call(channel: channel)
      expect(result).not_to have_key("config")
    end

    it "includes enabled when set" do
      channel = build_channel(enabled: false)
      result  = described_class.call(channel: channel)
      expect(result["enabled"]).to be false
    end

    it "includes all supported channel types" do
      %w[slack discord telegram whatsapp signal web].each do |type|
        channel = build_channel(channel_type: type)
        result  = described_class.call(channel: channel)
        expect(result["type"]).to eq(type)
      end
    end
  end
end
