# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Deployers::ChannelsDeployer do
  def build_document(channels: [])
    Swarms::SwarmDocument.new(
      swarm_version: "1.0",
      name:          "Test Swarm",
      channels:      channels
    )
  end

  # ---------------------------------------------------------------------------
  # Result contract
  # ---------------------------------------------------------------------------

  describe "result contract" do
    it "always returns a successful ServiceResponse" do
      result = described_class.call(document: build_document)
      expect(result).to be_success
    end

    it "returns an empty channels array when the document has no channels" do
      result = described_class.call(document: build_document(channels: []))
      expect(result.payload[:channels]).to eq([])
    end

    it "returns one DeployResult per channel in the document" do
      doc = build_document(channels: [
        { "name" => "channel-a", "type" => "slack" },
        { "name" => "channel-b", "type" => "discord" }
      ])
      result = described_class.call(document: doc)
      expect(result.payload[:channels].size).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # No conflict — create
  # ---------------------------------------------------------------------------

  describe "when no platform channel exists with that name" do
    it "creates a new Channel record" do
      doc = build_document(channels: [{ "name" => "my-channel", "type" => "slack" }])
      expect { described_class.call(document: doc) }.to change(Channel, :count).by(1)
    end

    it "returns action :created" do
      doc    = build_document(channels: [{ "name" => "my-channel", "type" => "slack" }])
      result = described_class.call(document: doc)
      expect(result.payload[:channels].first.action).to eq(:created)
    end

    it "stores the channel_type from the swarm type field" do
      doc     = build_document(channels: [{ "name" => "test-channel", "type" => "discord" }])
      result  = described_class.call(document: doc)
      channel = result.payload[:channels].first.record
      expect(channel.channel_type).to eq("discord")
    end

    it "stores config when provided" do
      doc    = build_document(channels: [{
        "name"   => "test-channel",
        "type"   => "slack",
        "config" => { "webhook_url" => "https://hooks.slack.com/xyz" }
      }])
      channel = described_class.call(document: doc).payload[:channels].first.record
      expect(channel.config["webhook_url"]).to eq("https://hooks.slack.com/xyz")
    end

    it "defaults enabled to true when not specified" do
      doc     = build_document(channels: [{ "name" => "test-channel", "type" => "slack" }])
      channel = described_class.call(document: doc).payload[:channels].first.record
      expect(channel.enabled).to be true
    end

    it "respects an explicit enabled: false" do
      doc     = build_document(channels: [{ "name" => "test-channel", "type" => "slack", "enabled" => false }])
      channel = described_class.call(document: doc).payload[:channels].first.record
      expect(channel.enabled).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # Conflict — no resolution (default skip)
  # ---------------------------------------------------------------------------

  describe "when a channel already exists and no resolution is provided" do
    let!(:existing) { Channel.create!(name: "my-channel", channel_type: "slack") }

    it "does not create a new Channel record" do
      doc = build_document(channels: [{ "name" => "my-channel", "type" => "discord" }])
      expect { described_class.call(document: doc) }.not_to change(Channel, :count)
    end

    it "returns action :skipped" do
      doc    = build_document(channels: [{ "name" => "my-channel", "type" => "discord" }])
      result = described_class.call(document: doc)
      expect(result.payload[:channels].first.action).to eq(:skipped)
    end

    it "returns the existing record unchanged" do
      doc    = build_document(channels: [{ "name" => "my-channel", "type" => "discord" }])
      result = described_class.call(document: doc)
      expect(result.payload[:channels].first.record).to eq(existing)
      expect(existing.reload.channel_type).to eq("slack")
    end
  end

  # ---------------------------------------------------------------------------
  # Conflict — :skip resolution
  # ---------------------------------------------------------------------------

  describe "resolution :skip" do
    let!(:existing) { Channel.create!(name: "my-channel", channel_type: "slack") }

    it "keeps the existing record and returns :skipped" do
      doc    = build_document(channels: [{ "name" => "my-channel", "type" => "discord" }])
      result = described_class.call(document: doc, resolutions: { "my-channel" => :skip })
      expect(result.payload[:channels].first.action).to eq(:skipped)
      expect(existing.reload.channel_type).to eq("slack")
    end
  end

  # ---------------------------------------------------------------------------
  # Conflict — :overwrite resolution
  # ---------------------------------------------------------------------------

  describe "resolution :overwrite" do
    let!(:existing) { Channel.create!(name: "my-channel", channel_type: "slack") }

    it "updates the existing record and returns :updated" do
      doc    = build_document(channels: [{ "name" => "my-channel", "type" => "discord" }])
      result = described_class.call(document: doc, resolutions: { "my-channel" => :overwrite })
      expect(result.payload[:channels].first.action).to eq(:updated)
      expect(existing.reload.channel_type).to eq("discord")
    end

    it "does not create a new Channel record" do
      doc = build_document(channels: [{ "name" => "my-channel", "type" => "discord" }])
      expect { described_class.call(document: doc, resolutions: { "my-channel" => :overwrite }) }
        .not_to change(Channel, :count)
    end
  end

  # ---------------------------------------------------------------------------
  # Conflict — :rename resolution
  # ---------------------------------------------------------------------------

  describe "resolution :rename" do
    let!(:existing) { Channel.create!(name: "my-channel", channel_type: "slack") }

    it "creates a new Channel with a suffixed name and returns :renamed" do
      doc    = build_document(channels: [{ "name" => "my-channel", "type" => "discord" }])
      result = described_class.call(document: doc, resolutions: { "my-channel" => :rename })
      dr     = result.payload[:channels].first
      expect(dr.action).to eq(:renamed)
      expect(dr.name).to eq("my-channel-2")
      expect(dr.record.channel_type).to eq("discord")
    end

    it "increments the suffix when -2 is also taken" do
      Channel.create!(name: "my-channel-2", channel_type: "slack")
      doc    = build_document(channels: [{ "name" => "my-channel", "type" => "discord" }])
      result = described_class.call(document: doc, resolutions: { "my-channel" => :rename })
      expect(result.payload[:channels].first.name).to eq("my-channel-3")
    end
  end
end
