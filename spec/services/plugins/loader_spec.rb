# frozen_string_literal: true

require "rails_helper"

RSpec.describe Plugins::Loader do
  before do
    Plugins::Registry.reset!
    Plugins::Hooks.reset!
    Channels::Registry.reset_plugin_adapters!
    Tools::Executor.reset_plugin_executors!
  end

  after do
    Plugins::Registry.reset!
    Plugins::Hooks.reset!
    Channels::Registry.reset_plugin_adapters!
    Tools::Executor.reset_plugin_executors!
  end

  describe ".load_all" do
    it "returns success with empty loaded list when plugin dir does not exist" do
      allow(Plugins::Loader::PLUGIN_DIR).to receive(:exist?).and_return(false)

      result = described_class.load_all
      expect(result).to be_success
      expect(result.data[:loaded]).to eq([])
    end

    it "loads plugins from subdirectories" do
      Dir.mktmpdir do |dir|
        plugin_dir = Pathname.new(dir)
        stub_const("Plugins::Loader::PLUGIN_DIR", plugin_dir)

        plugin_path = plugin_dir.join("my-plugin")
        FileUtils.mkdir_p(plugin_path)
        File.write(plugin_path.join("hivemind-plugin.yml"), {
          "name" => "my-plugin",
          "version" => "1.0.0",
          "description" => "Test"
        }.to_yaml)

        result = described_class.load_all
        expect(result).to be_success
        expect(result.data[:loaded]).to include("my-plugin")
        expect(Plugins::Registry.active?("my-plugin")).to be true
      end
    end

    it "collects errors from invalid plugins" do
      Dir.mktmpdir do |dir|
        plugin_dir = Pathname.new(dir)
        stub_const("Plugins::Loader::PLUGIN_DIR", plugin_dir)

        FileUtils.mkdir_p(plugin_dir.join("bad-plugin"))

        result = described_class.load_all
        expect(result).to be_success
        expect(result.data[:errors]).not_to be_empty
      end
    end
  end

  describe ".load_plugin" do
    it "loads a valid plugin and registers it" do
      Dir.mktmpdir do |dir|
        plugin_path = Pathname.new(dir)
        File.write(plugin_path.join("hivemind-plugin.yml"), {
          "name" => "good-plugin",
          "version" => "1.0.0"
        }.to_yaml)

        result = described_class.load_plugin(plugin_path)
        expect(result).to be_success
        expect(result.data[:plugin_name]).to eq("good-plugin")
      end
    end

    it "returns failure when manifest is missing" do
      Dir.mktmpdir do |dir|
        result = described_class.load_plugin(Pathname.new(dir))
        expect(result).not_to be_success
        expect(result.error).to include("No manifest")
      end
    end

    it "registers channel extension points" do
      Dir.mktmpdir do |dir|
        plugin_path = Pathname.new(dir)
        File.write(plugin_path.join("hivemind-plugin.yml"), {
          "name" => "channel-plugin",
          "version" => "1.0.0",
          "extension_points" => [
            { "type" => "channel", "id" => "custom_chat", "class_name" => "CustomChatAdapter" }
          ]
        }.to_yaml)

        described_class.load_plugin(plugin_path)
        expect(Channels::Registry.plugin_registered?("custom_chat")).to be true
      end
    end

    it "registers hook extension points" do
      Dir.mktmpdir do |dir|
        plugin_path = Pathname.new(dir)
        File.write(plugin_path.join("hivemind-plugin.yml"), {
          "name" => "hook-plugin",
          "version" => "1.0.0",
          "extension_points" => [
            { "type" => "hook", "id" => "after_chat", "class_name" => "MyHook" }
          ]
        }.to_yaml)

        stub_const("MyHook", Class.new { def call(_); end })
        described_class.load_plugin(plugin_path)
        expect(Plugins::Hooks.registered_for("after_chat")).not_to be_empty
      end
    end

    it "loads Ruby files from lib/ directory" do
      Dir.mktmpdir do |dir|
        plugin_path = Pathname.new(dir)
        lib_dir = plugin_path.join("lib")
        FileUtils.mkdir_p(lib_dir)

        File.write(plugin_path.join("hivemind-plugin.yml"), {
          "name" => "lib-plugin",
          "version" => "1.0.0"
        }.to_yaml)

        File.write(lib_dir.join("test_loader_check.rb"), "TEST_LOADER_CHECK_LOADED = true")

        described_class.load_plugin(plugin_path)
        expect(defined?(TEST_LOADER_CHECK_LOADED)).to be_truthy
      end
    end
  end
end
