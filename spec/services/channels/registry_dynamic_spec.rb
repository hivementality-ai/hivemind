# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::Registry, "dynamic registration" do
  before { described_class.reset_plugin_adapters! }
  after { described_class.reset_plugin_adapters! }

  describe "BUILTIN_ADAPTERS" do
    it "contains all built-in channel types" do
      expect(Channels::Registry::BUILTIN_ADAPTERS).to include(
        "discord" => "Channels::DiscordAdapter",
        "slack" => "Channels::SlackAdapter",
        "telegram" => "Channels::TelegramAdapter",
        "whatsapp" => "Channels::WhatsappAdapter",
        "signal" => "Channels::SignalAdapter"
      )
    end

    it "is frozen" do
      expect(Channels::Registry::BUILTIN_ADAPTERS).to be_frozen
    end
  end

  describe "ADAPTERS backwards compatibility" do
    it "aliases ADAPTERS to BUILTIN_ADAPTERS" do
      expect(Channels::Registry::ADAPTERS).to eq(Channels::Registry::BUILTIN_ADAPTERS)
    end
  end

  describe ".register" do
    it "registers a new adapter type" do
      described_class.register("custom_chat", "Plugins::CustomChatAdapter")

      expect(described_class.registered?("custom_chat")).to be true
      expect(described_class.plugin_registered?("custom_chat")).to be true
    end

    it "accepts symbol type and class name" do
      described_class.register(:my_adapter, :MyAdapterClass)

      expect(described_class.registered?("my_adapter")).to be true
    end
  end

  describe ".unregister" do
    it "removes a plugin adapter" do
      described_class.register("custom", "CustomAdapter")
      described_class.unregister("custom")

      expect(described_class.plugin_registered?("custom")).to be false
      expect(described_class.registered?("custom")).to be false
    end

    it "does not affect builtin adapters" do
      described_class.unregister("discord")
      expect(described_class.registered?("discord")).to be true
      expect(described_class.builtin?("discord")).to be true
    end
  end

  describe ".supported_types" do
    it "includes builtin types" do
      types = described_class.supported_types
      expect(types).to include("discord", "slack", "telegram", "whatsapp", "signal")
    end

    it "includes plugin types" do
      described_class.register("custom", "CustomAdapter")
      expect(described_class.supported_types).to include("custom")
    end
  end

  describe ".registered?" do
    it "returns true for builtin types" do
      expect(described_class.registered?("discord")).to be true
    end

    it "returns true for plugin types" do
      described_class.register("custom", "CustomAdapter")
      expect(described_class.registered?("custom")).to be true
    end

    it "returns false for unknown types" do
      expect(described_class.registered?("nonexistent")).to be false
    end
  end

  describe ".builtin?" do
    it "returns true for builtin types" do
      expect(described_class.builtin?("discord")).to be true
    end

    it "returns false for plugin types" do
      described_class.register("custom", "CustomAdapter")
      expect(described_class.builtin?("custom")).to be false
    end
  end

  describe ".plugin_registered?" do
    it "returns true for plugin types" do
      described_class.register("custom", "CustomAdapter")
      expect(described_class.plugin_registered?("custom")).to be true
    end

    it "returns false for builtin types" do
      expect(described_class.plugin_registered?("discord")).to be false
    end
  end

  describe ".reset_plugin_adapters!" do
    it "clears all plugin adapters" do
      described_class.register("custom_a", "AdapterA")
      described_class.register("custom_b", "AdapterB")
      described_class.reset_plugin_adapters!

      expect(described_class.plugin_registered?("custom_a")).to be false
      expect(described_class.plugin_registered?("custom_b")).to be false
    end

    it "preserves builtin adapters" do
      described_class.register("custom", "Custom")
      described_class.reset_plugin_adapters!

      expect(described_class.registered?("discord")).to be true
      expect(described_class.builtin?("discord")).to be true
    end
  end

  describe ".adapter_for with plugin adapter" do
    it "resolves plugin adapters" do
      stub_const("Plugins::CustomAdapter", Class.new do
        def initialize(channel); end
      end)

      described_class.register("custom", "Plugins::CustomAdapter")
      channel = double("Channel", channel_type: "custom")

      adapter = described_class.adapter_for(channel)
      expect(adapter).to be_a(Plugins::CustomAdapter)
    end

    it "plugin adapters override builtins with same type" do
      stub_const("Plugins::OverrideDiscord", Class.new do
        def initialize(channel); end
      end)

      described_class.register("discord", "Plugins::OverrideDiscord")
      channel = double("Channel", channel_type: "discord")

      adapter = described_class.adapter_for(channel)
      expect(adapter).to be_a(Plugins::OverrideDiscord)
    end
  end
end
