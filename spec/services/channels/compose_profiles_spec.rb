# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Channels::ComposeProfiles do
  describe ".for_types" do
    it "needs nothing for webhook-only channels" do
      expect(described_class.for_types(%w[discord email msteams])).to eq([])
    end

    it "needs the connector for connector-served channels" do
      %w[slack telegram whatsapp].each do |type|
        expect(described_class.for_types([ type ])).to eq([ "channels" ])
      end
    end

    it "needs the connector and signal-cli for signal" do
      expect(described_class.for_types(%w[signal])).to eq(%w[channels signal])
    end
  end

  describe ".needed" do
    it "is empty with no channels" do
      expect(described_class.needed).to eq([])
    end

    it "ignores disabled channels" do
      create(:channel, channel_type: "signal", enabled: false)

      expect(described_class.needed).to eq([])
    end

    it "covers every enabled channel" do
      create(:channel, channel_type: "telegram", enabled: true)
      create(:channel, channel_type: "signal", enabled: true)

      expect(described_class.needed).to contain_exactly("channels", "signal")
    end
  end

  describe ".merge" do
    it "combines lists in order without blanks or repeats" do
      expect(described_class.merge("tunnel, channels", nil, "channels,signal", "")).to eq("tunnel,channels,signal")
    end
  end

  describe ".persist" do
    let(:path) { File.join(Dir.mktmpdir, ".env") }

    it "appends COMPOSE_PROFILES when absent" do
      File.write(path, "A=1")

      expect(described_class.persist(%w[channels], path: path)).to be(true)
      expect(File.read(path)).to eq("A=1\nCOMPOSE_PROFILES=channels\n")
    end

    it "merges into an existing line and then does nothing" do
      File.write(path, "A=1\nCOMPOSE_PROFILES=tunnel\nB=2\n")

      expect(described_class.persist(%w[channels signal], path: path)).to be(true)
      expect(File.read(path)).to eq("A=1\nCOMPOSE_PROFILES=tunnel,channels,signal\nB=2\n")
      expect(described_class.persist(%w[channels signal], path: path)).to be(false)
    end

    it "does nothing without a file or profiles" do
      expect(described_class.persist(%w[channels], path: "/nonexistent/.env")).to be(false)
      File.write(path, "A=1\n")
      expect(described_class.persist([], path: path)).to be(false)
    end
  end

  describe ".ensure_running" do
    let(:manager) { instance_double(RemoteAccess::ConnectorManager, up: ServiceResponse.success) }

    before do
      allow(RemoteAccess::ConnectorManager).to receive(:new).and_return(manager)
      allow(described_class).to receive(:persist)
    end

    it "starts the connector and signal-cli for a signal channel" do
      described_class.ensure_running(build(:channel, channel_type: "signal", enabled: true))

      expect(described_class).to have_received(:persist).with(%w[channels signal])
      expect(manager).to have_received(:up).with(%w[connector signal-cli], profiles: %w[channels signal])
    end

    it "does nothing for disabled or webhook-only channels" do
      described_class.ensure_running(build(:channel, channel_type: "signal", enabled: false))
      described_class.ensure_running(build(:channel, channel_type: "discord", enabled: true))

      expect(manager).not_to have_received(:up)
    end
  end
end
