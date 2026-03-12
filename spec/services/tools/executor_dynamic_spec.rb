# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::Executor, "dynamic registration" do
  before { described_class.reset_plugin_executors! }

  describe "BUILTIN_EXECUTORS" do
    it "contains all built-in executor types" do
      expect(Tools::Executor::BUILTIN_EXECUTORS).to include(
        "shell" => Tools::ShellExecutor,
        "file_read" => Tools::FileReadExecutor,
        "web_search" => Tools::WebSearchExecutor
      )
    end

    it "is frozen" do
      expect(Tools::Executor::BUILTIN_EXECUTORS).to be_frozen
    end
  end

  describe "EXECUTORS backwards compatibility" do
    it "aliases EXECUTORS to BUILTIN_EXECUTORS" do
      expect(Tools::Executor::EXECUTORS).to eq(Tools::Executor::BUILTIN_EXECUTORS)
    end
  end

  describe ".register" do
    it "registers a new executor class" do
      custom_executor = Class.new
      described_class.register("custom_tool", custom_executor)

      expect(described_class.registered?("custom_tool")).to be true
      expect(described_class.all_executors["custom_tool"]).to eq(custom_executor)
    end

    it "constantizes string class names" do
      stub_const("Plugins::MyExecutor", Class.new)
      described_class.register("my_tool", "Plugins::MyExecutor")

      expect(described_class.all_executors["my_tool"]).to eq(Plugins::MyExecutor)
    end
  end

  describe ".unregister" do
    it "removes a plugin executor" do
      custom = Class.new
      described_class.register("custom", custom)
      described_class.unregister("custom")

      expect(described_class.registered?("custom")).to be false
    end

    it "does not affect builtin executors" do
      described_class.unregister("shell")
      expect(described_class.registered?("shell")).to be true
    end
  end

  describe ".all_executors" do
    it "merges builtin and plugin executors" do
      custom = Class.new
      described_class.register("plugin_tool", custom)

      all = described_class.all_executors
      expect(all).to include("shell" => Tools::ShellExecutor)
      expect(all).to include("plugin_tool" => custom)
    end
  end

  describe ".registered?" do
    it "returns true for builtin executors" do
      expect(described_class.registered?("shell")).to be true
    end

    it "returns true for plugin executors" do
      described_class.register("custom", Class.new)
      expect(described_class.registered?("custom")).to be true
    end

    it "returns false for unknown executors" do
      expect(described_class.registered?("nonexistent")).to be false
    end
  end

  describe ".reset_plugin_executors!" do
    it "clears all plugin executors" do
      described_class.register("a", Class.new)
      described_class.register("b", Class.new)
      described_class.reset_plugin_executors!

      expect(described_class.registered?("a")).to be false
      expect(described_class.registered?("b")).to be false
    end

    it "preserves builtin executors" do
      described_class.register("custom", Class.new)
      described_class.reset_plugin_executors!

      expect(described_class.registered?("shell")).to be true
    end
  end
end
