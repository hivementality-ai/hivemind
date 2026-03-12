# frozen_string_literal: true

require "rails_helper"

RSpec.describe Plugins::Registry do
  let(:manifest) do
    Plugins::Manifest.new(data: {
      "name" => "test-plugin",
      "version" => "1.0.0",
      "description" => "Test plugin",
      "extension_points" => [
        { "type" => "channel", "id" => "custom", "class_name" => "CustomAdapter" }
      ]
    })
  end

  before { described_class.reset! }

  describe ".register_plugin" do
    it "registers a plugin" do
      before_time = Time.current
      described_class.register_plugin(name: "test-plugin", manifest: manifest, path: "/plugins/test")
      after_time = Time.current

      plugin = described_class.find("test-plugin")
      expect(plugin).not_to be_nil
      expect(plugin[:name]).to eq("test-plugin")
      expect(plugin[:manifest]).to eq(manifest)
      expect(plugin[:path]).to eq("/plugins/test")
      expect(plugin[:status]).to eq(:active)
      expect(plugin[:loaded_at]).to be_between(before_time, after_time)
    end
  end

  describe ".unregister_plugin" do
    it "removes a registered plugin" do
      described_class.register_plugin(name: "test-plugin", manifest: manifest, path: "/plugins/test")
      described_class.unregister_plugin("test-plugin")

      expect(described_class.find("test-plugin")).to be_nil
    end
  end

  describe ".loaded" do
    it "returns only active plugins" do
      described_class.register_plugin(name: "active-one", manifest: manifest, path: "/p/1")
      described_class.register_plugin(name: "active-two", manifest: manifest, path: "/p/2")
      described_class.disable("active-two")

      loaded = described_class.loaded
      expect(loaded.size).to eq(1)
      expect(loaded.first[:name]).to eq("active-one")
    end
  end

  describe ".find" do
    it "returns nil for unknown plugin" do
      expect(described_class.find("nonexistent")).to be_nil
    end
  end

  describe ".extension_points_for" do
    it "returns extension points of given type from active plugins" do
      described_class.register_plugin(name: "test-plugin", manifest: manifest, path: "/p/1")

      channel_exts = described_class.extension_points_for("channel")
      expect(channel_exts.size).to eq(1)
      expect(channel_exts.first.id).to eq("custom")
    end

    it "excludes extension points from disabled plugins" do
      described_class.register_plugin(name: "test-plugin", manifest: manifest, path: "/p/1")
      described_class.disable("test-plugin")

      expect(described_class.extension_points_for("channel")).to be_empty
    end
  end

  describe ".active?" do
    it "returns true for active plugin" do
      described_class.register_plugin(name: "test-plugin", manifest: manifest, path: "/p/1")
      expect(described_class.active?("test-plugin")).to be true
    end

    it "returns false for disabled plugin" do
      described_class.register_plugin(name: "test-plugin", manifest: manifest, path: "/p/1")
      described_class.disable("test-plugin")
      expect(described_class.active?("test-plugin")).to be false
    end

    it "returns false for unknown plugin" do
      expect(described_class.active?("nonexistent")).to be false
    end
  end

  describe ".disable" do
    it "disables an active plugin" do
      described_class.register_plugin(name: "test-plugin", manifest: manifest, path: "/p/1")

      result = described_class.disable("test-plugin")
      expect(result).to be_success
      expect(result.data[:status]).to eq(:disabled)
      expect(described_class.active?("test-plugin")).to be false
    end

    it "returns failure for unknown plugin" do
      result = described_class.disable("nonexistent")
      expect(result).not_to be_success
      expect(result.error).to include("Plugin not found")
    end
  end

  describe ".enable" do
    it "enables a disabled plugin" do
      described_class.register_plugin(name: "test-plugin", manifest: manifest, path: "/p/1")
      described_class.disable("test-plugin")

      result = described_class.enable("test-plugin")
      expect(result).to be_success
      expect(result.data[:status]).to eq(:active)
      expect(described_class.active?("test-plugin")).to be true
    end

    it "returns failure for unknown plugin" do
      result = described_class.enable("nonexistent")
      expect(result).not_to be_success
      expect(result.error).to include("Plugin not found")
    end
  end

  describe ".count" do
    it "returns the total number of registered plugins" do
      expect(described_class.count).to eq(0)
      described_class.register_plugin(name: "one", manifest: manifest, path: "/p/1")
      described_class.register_plugin(name: "two", manifest: manifest, path: "/p/2")
      expect(described_class.count).to eq(2)
    end
  end

  describe ".reset!" do
    it "clears all plugins" do
      described_class.register_plugin(name: "test-plugin", manifest: manifest, path: "/p/1")
      described_class.reset!
      expect(described_class.count).to eq(0)
      expect(described_class.loaded).to be_empty
    end
  end
end
