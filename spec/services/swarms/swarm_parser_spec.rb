# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::SwarmParser do
  def minimal_json
    JSON.generate({ swarm_version: "1.0", name: "Test Swarm" })
  end

  def full_json
    JSON.generate({
      swarm_version: "1.0",
      name: "Full Swarm",
      slug: "full-swarm",
      description: "A complete swarm",
      author: { name: "Author", url: "https://author.dev", email: "author@dev.io" },
      version: "1.2.3",
      license: "MIT",
      tags: ["test", "example"],
      icon: "🤖",
      homepage: "https://swarm.example.com",
      requires: {
        hivemind_version: ">=2.0",
        integrations: ["github"],
        provider_models: ["claude-3-5-sonnet"]
      },
      team: { name: "Test Team", description: "A test team" },
      agents: [{ name: "Agent One", role: "Engineer" }],
      skills: [{ name: "skill-one", summary: "Does stuff" }],
      tools: [{ name: "tool-one", description: "A tool" }],
      channels: [{ ref: "main-slack", name: "Main Slack", type: "slack" }],
      mcp_servers: [{ name: "my-mcp", transport: "stdio", command: "npx my-mcp" }],
      api_integrations: [{
        name: "my-api",
        base_url: "https://api.example.com",
        endpoints: [{ method: "GET", path: "/v1/resources" }]
      }],
      variables: {
        "API_KEY" => { description: "API key", required: true, type: "string" }
      }
    })
  end

  # ---------------------------------------------------------------------------
  # Input validation
  # ---------------------------------------------------------------------------
  describe "input validation" do
    it "returns error when neither path nor json is provided" do
      result = described_class.call
      expect(result).to be_error
      expect(result.message).to include("Must provide")
    end

    it "requires .swarm.json extension" do
      result = described_class.call(path: "/tmp/team.json")
      expect(result).to be_error
      expect(result.message).to include(".swarm.json")
    end

    it "returns error when file does not exist" do
      result = described_class.call(path: "/tmp/nonexistent.swarm.json")
      expect(result).to be_error
      expect(result.message).to include("not found")
    end

    it "returns error for invalid JSON" do
      result = described_class.call(json: "{ bad json }")
      expect(result).to be_error
      expect(result.message).to include("Invalid JSON")
    end
  end

  # ---------------------------------------------------------------------------
  # Schema validation errors
  # ---------------------------------------------------------------------------
  describe "schema validation" do
    it "returns error for invalid swarm" do
      result = described_class.call(json: JSON.generate({ swarm_version: "1.0" }))
      expect(result).to be_error
      expect(result.message).to include("invalid")
      expect(result.payload[:errors]).to be_an(Array)
      expect(result.payload[:errors]).not_to be_empty
    end

    it "includes all validation errors in payload" do
      result = described_class.call(json: JSON.generate({ swarm_version: "99.0", name: 42 }))
      expect(result).to be_error
      expect(result.payload[:errors]).to include(match(/unsupported swarm_version/))
      expect(result.payload[:errors]).to include("name must be a string")
    end
  end

  # ---------------------------------------------------------------------------
  # Successful parsing
  # ---------------------------------------------------------------------------
  describe "successful parsing" do
    it "returns success for minimal valid swarm" do
      result = described_class.call(json: minimal_json)
      expect(result).to be_success
    end

    it "returns a SwarmDocument as payload" do
      result = described_class.call(json: minimal_json)
      expect(result.payload).to be_a(Swarms::SwarmDocument)
    end

    it "populates swarm_version and name" do
      result = described_class.call(json: minimal_json)
      doc = result.payload
      expect(doc.swarm_version).to eq("1.0")
      expect(doc.name).to eq("Test Swarm")
    end

    it "populates all fields from full swarm JSON" do
      result = described_class.call(json: full_json)
      expect(result).to be_success

      doc = result.payload
      expect(doc.slug).to eq("full-swarm")
      expect(doc.description).to eq("A complete swarm")
      expect(doc.version).to eq("1.2.3")
      expect(doc.license).to eq("MIT")
      expect(doc.tags).to eq(["test", "example"])
      expect(doc.homepage).to eq("https://swarm.example.com")
    end

    it "builds SwarmAuthor from author hash" do
      result = described_class.call(json: full_json)
      doc = result.payload
      expect(doc.author).to be_a(Swarms::SwarmDocument::SwarmAuthor)
      expect(doc.author.name).to eq("Author")
      expect(doc.author.url).to eq("https://author.dev")
      expect(doc.author.email).to eq("author@dev.io")
    end

    it "builds SwarmRequirements from requires hash" do
      result = described_class.call(json: full_json)
      doc = result.payload
      expect(doc.requires).to be_a(Swarms::SwarmDocument::SwarmRequirements)
      expect(doc.requires.hivemind_version).to eq(">=2.0")
      expect(doc.requires.integrations).to eq(["github"])
      expect(doc.requires.provider_models).to eq(["claude-3-5-sonnet"])
    end

    it "builds SwarmTeam from team hash" do
      result = described_class.call(json: full_json)
      doc = result.payload
      expect(doc.team).to be_a(Swarms::SwarmDocument::SwarmTeam)
      expect(doc.team.name).to eq("Test Team")
    end

    it "populates agents array" do
      result = described_class.call(json: full_json)
      doc = result.payload
      expect(doc.agent_count).to eq(1)
      expect(doc.agents.first["name"]).to eq("Agent One")
    end

    it "populates channels array" do
      result = described_class.call(json: full_json)
      doc = result.payload
      expect(doc.channel_count).to eq(1)
      expect(doc.channels.first["ref"]).to eq("main-slack")
    end

    it "builds variables as SwarmVariable objects" do
      result = described_class.call(json: full_json)
      doc = result.payload
      expect(doc.variables).to have_key("API_KEY")
      var = doc.variables["API_KEY"]
      expect(var).to be_a(Swarms::SwarmDocument::SwarmVariable)
      expect(var.description).to eq("API key")
      expect(var.required).to be(true)
      expect(var.type).to eq("string")
    end

    it "returns empty variables hash when no variables defined" do
      result = described_class.call(json: minimal_json)
      expect(result.payload.variables).to eq({})
    end

    it "returns nil author when no author defined" do
      result = described_class.call(json: minimal_json)
      expect(result.payload.author).to be_nil
    end

    it "returns nil requires when no requires defined" do
      result = described_class.call(json: minimal_json)
      expect(result.payload.requires).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # File loading
  # ---------------------------------------------------------------------------
  describe "loading from file path" do
    let(:tmp_path) { "/tmp/test.swarm.json" }

    after { File.delete(tmp_path) if File.exist?(tmp_path) }

    it "reads and parses a valid .swarm.json file" do
      File.write(tmp_path, minimal_json)
      result = described_class.call(path: tmp_path)
      expect(result).to be_success
      expect(result.payload.name).to eq("Test Swarm")
    end

    it "returns error for oversized file" do
      File.write(tmp_path, ("x" * (5 * 1024 * 1024 + 1)))
      result = described_class.call(path: tmp_path)
      expect(result).to be_error
      expect(result.message).to include("5MB")
    end
  end
end

  # ---------------------------------------------------------------------------
  # SwarmValidator integration — referential integrity & uniqueness
  # ---------------------------------------------------------------------------
  describe "validator integration" do
    def swarm_with(**overrides)
      base = {
        swarm_version: "1.0",
        name: "Test Swarm",
        agents: [{ name: "Agent One", role: "Engineer" }],
        skills: [{ name: "skill-one" }],
        tools:  [{ name: "tool-one" }],
        channels: [{ ref: "ch-slack", name: "Slack", type: "slack" }]
      }
      JSON.generate(base.merge(overrides))
    end

    it "rejects a swarm where an agent references a non-existent skill" do
      json = JSON.generate({
        swarm_version: "1.0",
        name: "Bad Refs",
        agents: [{ name: "Agent", role: "Eng", skills: ["missing-skill"] }]
      })
      result = described_class.call(json: json)
      expect(result).to be_error
      expect(result.payload[:errors]).to include(match(/missing-skill/))
    end

    it "rejects a swarm with duplicate agent names" do
      json = JSON.generate({
        swarm_version: "1.0",
        name: "Dupe Agents",
        agents: [
          { name: "Mando", role: "Engineer" },
          { name: "Mando", role: "Reviewer" }
        ]
      })
      result = described_class.call(json: json)
      expect(result).to be_error
      expect(result.payload[:errors]).to include(match(/duplicate.*Mando/i))
    end

    it "rejects a swarm where an agent channel_ref does not exist in channels[]" do
      json = JSON.generate({
        swarm_version: "1.0",
        name: "Bad Channel Ref",
        agents: [{ name: "A", role: "B", channels: [{ channel_ref: "ghost-channel" }] }],
        channels: [{ ref: "real-channel", name: "Real", type: "slack" }]
      })
      result = described_class.call(json: json)
      expect(result).to be_error
      expect(result.payload[:errors]).to include(match(/ghost-channel/))
    end

    it "passes a structurally valid swarm with consistent cross-references" do
      json = JSON.generate({
        swarm_version: "1.0",
        name: "Consistent Swarm",
        agents: [
          {
            name: "Mando",
            role: "Engineer",
            skills: ["my-skill"],
            tools: ["my-tool"],
            channels: [{ channel_ref: "main-slack" }]
          }
        ],
        skills: [{ name: "my-skill" }],
        tools:  [{ name: "my-tool" }],
        channels: [{ ref: "main-slack", name: "Main Slack", type: "slack" }]
      })
      result = described_class.call(json: json)
      expect(result).to be_success
    end

    it "does not run SwarmValidator when SwarmSchema fails" do
      # A structurally broken doc (no name) — validator should not fire
      json = JSON.generate({ swarm_version: "1.0" })
      result = described_class.call(json: json)
      expect(result).to be_error
      # Should get schema errors (plain strings), not validator errors (path: message format)
      expect(result.payload[:errors]).to all(be_a(String))
      expect(result.payload[:errors]).to include("name is required")
    end

    it "returns validator errors as plain strings (normalized from ValidationError structs)" do
      json = JSON.generate({
        swarm_version: "1.0",
        name: "Bad Refs",
        agents: [{ name: "Agent", role: "Eng", tools: ["no-such-tool"] }]
      })
      result = described_class.call(json: json)
      expect(result).to be_error
      expect(result.payload[:errors]).to all(be_a(String))
    end
  end
