# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Deployers::ToolsDeployer do
  def build_document(tools: [])
    Swarms::SwarmDocument.new(
      swarm_version: "1.0",
      name:          "Test Swarm",
      tools:         tools
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

    it "returns an empty tools array when the document has no tools" do
      result = described_class.call(document: build_document(tools: []))
      expect(result.payload[:tools]).to eq([])
    end

    it "returns one DeployResult per tool in the document" do
      doc    = build_document(tools: [
        { "name" => "tool-a", "description" => "A" },
        { "name" => "tool-b", "description" => "B" }
      ])
      result = described_class.call(document: doc)
      expect(result.payload[:tools].size).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # No conflict — create
  # ---------------------------------------------------------------------------

  describe "when no platform tool exists with that name" do
    it "creates a new Tool record" do
      doc = build_document(tools: [{ "name" => "my-tool", "description" => "Does things" }])
      expect { described_class.call(document: doc) }.to change(Tool, :count).by(1)
    end

    it "returns action :created" do
      doc    = build_document(tools: [{ "name" => "my-tool", "description" => "Desc" }])
      result = described_class.call(document: doc)
      expect(result.payload[:tools].first.action).to eq(:created)
    end

    it "sets executor_type to custom_script" do
      doc  = build_document(tools: [{ "name" => "script-tool", "description" => "A script" }])
      tool = described_class.call(document: doc).payload[:tools].first.record
      expect(tool.executor_type).to eq("custom_script")
    end

    it "stores script_template when provided" do
      doc  = build_document(tools: [{
        "name"            => "bash-tool",
        "description"     => "Runs bash",
        "script_template" => "#!/bin/bash\necho hello"
      }])
      tool = described_class.call(document: doc).payload[:tools].first.record
      expect(tool.script_template).to eq("#!/bin/bash\necho hello")
    end

    it "uses a TODO placeholder when script_template is absent" do
      doc  = build_document(tools: [{ "name" => "no-script", "description" => "Desc" }])
      tool = described_class.call(document: doc).payload[:tools].first.record
      expect(tool.script_template).to eq("# TODO: implement script")
    end

    it "defaults description to name when absent" do
      doc  = build_document(tools: [{ "name" => "unnamed-desc" }])
      tool = described_class.call(document: doc).payload[:tools].first.record
      expect(tool.description).to eq("unnamed-desc")
    end

    it "sets enabled true by default" do
      doc  = build_document(tools: [{ "name" => "enabled-tool", "description" => "D" }])
      tool = described_class.call(document: doc).payload[:tools].first.record
      expect(tool.enabled).to be true
    end

    it "sets builtin to false" do
      doc  = build_document(tools: [{ "name" => "custom-tool", "description" => "D" }])
      tool = described_class.call(document: doc).payload[:tools].first.record
      expect(tool.builtin).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # parameters_schema conversion
  # ---------------------------------------------------------------------------

  describe "parameters schema conversion" do
    it "converts swarm parameter definitions into JSON schema format" do
      doc  = build_document(tools: [{
        "name"        => "param-tool",
        "description" => "Parameterised",
        "parameters"  => {
          "target" => { "type" => "string", "description" => "The target host", "required" => true },
          "port"   => { "type" => "integer", "description" => "Port number", "required" => false }
        }
      }])
      tool   = described_class.call(document: doc).payload[:tools].first.record
      schema = tool.parameters_schema

      expect(schema["properties"]["target"]["type"]).to eq("string")
      expect(schema["properties"]["port"]["type"]).to eq("integer")
      expect(schema["required"]).to include("target")
      expect(schema["required"]).not_to include("port")
    end

    it "defaults parameter type to string when not specified" do
      doc    = build_document(tools: [{
        "name"        => "type-default",
        "description" => "D",
        "parameters"  => { "foo" => { "description" => "bar" } }
      }])
      tool = described_class.call(document: doc).payload[:tools].first.record
      expect(tool.parameters_schema.dig("properties", "foo", "type")).to eq("string")
    end

    it "returns empty schema when no parameters are provided" do
      doc  = build_document(tools: [{ "name" => "no-params", "description" => "D" }])
      tool = described_class.call(document: doc).payload[:tools].first.record
      expect(tool.parameters_schema).to eq({})
    end
  end

  # ---------------------------------------------------------------------------
  # Strategy: :skip
  # ---------------------------------------------------------------------------

  describe "strategy :skip" do
    it "returns the existing tool unchanged" do
      existing = create(:tool, name: "dupe-tool", description: "Old", executor_type: "custom_script", script_template: "old")
      doc      = build_document(tools: [{ "name" => "dupe-tool", "description" => "New" }])
      result   = described_class.call(document: doc, resolutions: { "dupe-tool" => :skip })

      dr = result.payload[:tools].first
      expect(dr.action).to eq(:skipped)
      expect(dr.record).to eq(existing)
      expect(existing.reload.description).to eq("Old")
    end

    it "does not create a new tool" do
      create(:tool, name: "dupe-tool", executor_type: "custom_script", script_template: "x")
      doc = build_document(tools: [{ "name" => "dupe-tool", "description" => "D" }])
      expect { described_class.call(document: doc, resolutions: { "dupe-tool" => :skip }) }.not_to change(Tool, :count)
    end
  end

  # ---------------------------------------------------------------------------
  # Strategy: :overwrite
  # ---------------------------------------------------------------------------

  describe "strategy :overwrite" do
    it "updates the existing tool's attributes" do
      existing = create(:tool, name: "my-tool", description: "Old desc", executor_type: "custom_script", script_template: "old")
      doc      = build_document(tools: [{
        "name"            => "my-tool",
        "description"     => "New desc",
        "script_template" => "new script"
      }])
      result = described_class.call(document: doc, resolutions: { "my-tool" => :overwrite })

      dr = result.payload[:tools].first
      expect(dr.action).to eq(:updated)
      expect(existing.reload.description).to eq("New desc")
      expect(existing.reload.script_template).to eq("new script")
    end
  end

  # ---------------------------------------------------------------------------
  # Strategy: :rename
  # ---------------------------------------------------------------------------

  describe "strategy :rename" do
    it "creates a new tool with a suffixed name" do
      create(:tool, name: "alpha-tool", executor_type: "custom_script", script_template: "x")
      doc    = build_document(tools: [{ "name" => "alpha-tool", "description" => "D" }])
      result = described_class.call(document: doc, resolutions: { "alpha-tool" => :rename })

      dr = result.payload[:tools].first
      expect(dr.action).to eq(:renamed)
      expect(dr.record.name).to eq("alpha-tool-2")
    end

    it "increments suffix when -2 already exists" do
      create(:tool, name: "alpha-tool",   executor_type: "custom_script", script_template: "x")
      create(:tool, name: "alpha-tool-2", executor_type: "custom_script", script_template: "x")
      doc    = build_document(tools: [{ "name" => "alpha-tool", "description" => "D" }])
      result = described_class.call(document: doc, resolutions: { "alpha-tool" => :rename })

      expect(result.payload[:tools].first.record.name).to eq("alpha-tool-3")
    end
  end

  # ---------------------------------------------------------------------------
  # Multiple tools
  # ---------------------------------------------------------------------------

  describe "with multiple tools" do
    it "creates all new tools" do
      doc = build_document(tools: [
        { "name" => "tool-1", "description" => "A" },
        { "name" => "tool-2", "description" => "B" }
      ])
      expect { described_class.call(document: doc) }.to change(Tool, :count).by(2)
    end

    it "handles mixed strategies independently" do
      create(:tool, name: "existing-tool", executor_type: "custom_script", script_template: "x")
      doc = build_document(tools: [
        { "name" => "existing-tool", "description" => "D" },
        { "name" => "brand-new",     "description" => "D" }
      ])
      result  = described_class.call(document: doc, resolutions: { "existing-tool" => :skip })
      actions = result.payload[:tools].map(&:action)

      expect(actions).to eq(%i[skipped created])
    end
  end
end
