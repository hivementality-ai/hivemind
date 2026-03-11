# frozen_string_literal: true

require "rails_helper"

RSpec.describe Plugins::Manifest do
  describe ".load" do
    it "loads a valid manifest from a YAML file" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "hivemind-plugin.yml")
        File.write(path, {
          "name" => "test-plugin",
          "version" => "1.0.0",
          "description" => "A test plugin"
        }.to_yaml)

        manifest = described_class.load(path: path)
        expect(manifest.name).to eq("test-plugin")
        expect(manifest.version).to eq("1.0.0")
        expect(manifest.description).to eq("A test plugin")
      end
    end

    it "raises ArgumentError when file does not exist" do
      expect {
        described_class.load(path: "/nonexistent/manifest.yml")
      }.to raise_error(ArgumentError, /Manifest not found/)
    end
  end

  describe "#initialize" do
    it "parses a valid manifest with all fields" do
      data = {
        "name" => "full-plugin",
        "version" => "2.0.0",
        "description" => "Full featured plugin",
        "author" => "Test Author",
        "extension_points" => [
          { "type" => "channel", "id" => "custom_chat", "class_name" => "CustomChatAdapter" }
        ],
        "dependencies" => {
          "gems" => [ "some_gem" ],
          "npm_packages" => [ "some-pkg" ]
        }
      }

      manifest = described_class.new(data: data)
      expect(manifest.name).to eq("full-plugin")
      expect(manifest.version).to eq("2.0.0")
      expect(manifest.author).to eq("Test Author")
      expect(manifest.extension_points.size).to eq(1)
      expect(manifest.extension_points.first.type).to eq("channel")
      expect(manifest.extension_points.first.id).to eq("custom_chat")
      expect(manifest.dependencies.gems).to eq([ "some_gem" ])
      expect(manifest.dependencies.npm_packages).to eq([ "some-pkg" ])
    end

    it "raises ArgumentError when name is missing" do
      data = { "version" => "1.0.0" }
      expect { described_class.new(data: data) }.to raise_error(ArgumentError, /Missing required field: name/)
    end

    it "raises ArgumentError when version is missing" do
      data = { "name" => "test" }
      expect { described_class.new(data: data) }.to raise_error(ArgumentError, /Missing required field: version/)
    end

    it "raises ArgumentError for invalid extension point type" do
      data = {
        "name" => "bad-ext",
        "version" => "1.0.0",
        "extension_points" => [
          { "type" => "invalid_type", "id" => "x", "class_name" => "X" }
        ]
      }
      expect { described_class.new(data: data) }.to raise_error(ArgumentError, /invalid type: invalid_type/)
    end

    it "raises ArgumentError for extension point missing id" do
      data = {
        "name" => "bad-ext",
        "version" => "1.0.0",
        "extension_points" => [
          { "type" => "channel", "class_name" => "X" }
        ]
      }
      expect { described_class.new(data: data) }.to raise_error(ArgumentError, /missing id/)
    end

    it "raises ArgumentError for extension point missing class_name" do
      data = {
        "name" => "bad-ext",
        "version" => "1.0.0",
        "extension_points" => [
          { "type" => "channel", "id" => "x" }
        ]
      }
      expect { described_class.new(data: data) }.to raise_error(ArgumentError, /missing class_name/)
    end

    it "raises ArgumentError when dependencies.gems is not an array" do
      data = {
        "name" => "bad-deps",
        "version" => "1.0.0",
        "dependencies" => { "gems" => "not_array" }
      }
      expect { described_class.new(data: data) }.to raise_error(ArgumentError, /dependencies.gems must be an array/)
    end

    it "defaults extension_points to empty array" do
      data = { "name" => "minimal", "version" => "1.0.0" }
      manifest = described_class.new(data: data)
      expect(manifest.extension_points).to eq([])
    end

    it "defaults dependencies to empty arrays" do
      data = { "name" => "minimal", "version" => "1.0.0" }
      manifest = described_class.new(data: data)
      expect(manifest.dependencies.gems).to eq([])
      expect(manifest.dependencies.npm_packages).to eq([])
    end

    it "accepts all valid extension types" do
      Plugins::Manifest::VALID_EXTENSION_TYPES.each do |type|
        data = {
          "name" => "type-test",
          "version" => "1.0.0",
          "extension_points" => [
            { "type" => type, "id" => "test_#{type}", "class_name" => "TestClass" }
          ]
        }
        manifest = described_class.new(data: data)
        expect(manifest.extension_points.first.type).to eq(type)
      end
    end

    it "handles nil data gracefully" do
      expect { described_class.new(data: nil) }.to raise_error(ArgumentError, /Missing required field/)
    end

    it "stores raw data" do
      data = { "name" => "raw-test", "version" => "1.0.0", "custom_key" => "custom_value" }
      manifest = described_class.new(data: data)
      expect(manifest.raw).to eq(data)
    end
  end
end
