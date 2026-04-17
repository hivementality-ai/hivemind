# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::SwarmDocument do
  # ---------------------------------------------------------------------------
  # SwarmAuthor
  # ---------------------------------------------------------------------------
  describe "SwarmAuthor" do
    subject(:klass) { described_class::SwarmAuthor }

    it "returns nil for nil input" do
      expect(klass.from_hash(nil)).to be_nil
    end

    it "builds from a hash" do
      author = klass.from_hash({ "name" => "Jane", "url" => "https://jane.dev", "email" => "jane@dev.io" })
      expect(author.name).to eq("Jane")
      expect(author.url).to eq("https://jane.dev")
      expect(author.email).to eq("jane@dev.io")
    end

    it "accepts symbol keys" do
      author = klass.from_hash({ name: "Jane", url: "https://jane.dev" })
      expect(author.name).to eq("Jane")
    end

    it "stores nil for missing optional fields" do
      author = klass.from_hash({ name: "Jane" })
      expect(author.url).to be_nil
      expect(author.email).to be_nil
    end

    it "returns an empty-field instance for empty hash" do
      author = klass.from_hash({})
      expect(author).not_to be_nil
      expect(author.name).to be_nil
    end

    it "is frozen" do
      author = klass.from_hash({ name: "Jane" })
      expect(author).to be_frozen
    end
  end

  # ---------------------------------------------------------------------------
  # SwarmRequirements
  # ---------------------------------------------------------------------------
  describe "SwarmRequirements" do
    subject(:klass) { described_class::SwarmRequirements }

    it "returns nil for nil input" do
      expect(klass.from_hash(nil)).to be_nil
    end

    it "returns an instance for an empty hash" do
      req = klass.from_hash({})
      expect(req).not_to be_nil
      expect(req.integrations).to eq([])
      expect(req.provider_models).to eq([])
      expect(req.hivemind_version).to be_nil
    end

    it "builds from a full hash" do
      req = klass.from_hash({
        "hivemind_version" => ">=2.0",
        "integrations" => ["github", "linear"],
        "provider_models" => ["claude-3-5-sonnet"]
      })
      expect(req.hivemind_version).to eq(">=2.0")
      expect(req.integrations).to eq(["github", "linear"])
      expect(req.provider_models).to eq(["claude-3-5-sonnet"])
    end

    it "accepts symbol keys" do
      req = klass.from_hash({ hivemind_version: ">=1.0", integrations: ["github"] })
      expect(req.hivemind_version).to eq(">=1.0")
    end

    it "coerces array items to strings" do
      req = klass.from_hash({ integrations: [:github], provider_models: [:claude] })
      expect(req.integrations).to eq(["github"])
      expect(req.provider_models).to eq(["claude"])
    end

    it "is frozen" do
      req = klass.from_hash({ hivemind_version: ">=1.0" })
      expect(req).to be_frozen
    end
  end

  # ---------------------------------------------------------------------------
  # SwarmTeam
  # ---------------------------------------------------------------------------
  describe "SwarmTeam" do
    subject(:klass) { described_class::SwarmTeam }

    it "returns nil for nil input" do
      expect(klass.from_hash(nil)).to be_nil
    end

    it "builds from a hash" do
      team = klass.from_hash({ name: "Dream Team", description: "Best team", custom_soul: "Be excellent" })
      expect(team.name).to eq("Dream Team")
      expect(team.description).to eq("Best team")
      expect(team.custom_soul).to eq("Be excellent")
    end

    it "returns instance for empty hash" do
      team = klass.from_hash({})
      expect(team).not_to be_nil
      expect(team.name).to be_nil
    end

    it "is frozen" do
      team = klass.from_hash({ name: "Dream Team" })
      expect(team).to be_frozen
    end
  end

  # ---------------------------------------------------------------------------
  # SwarmVariable
  # ---------------------------------------------------------------------------
  describe "SwarmVariable" do
    subject(:klass) { described_class::SwarmVariable }

    it "builds from a full hash" do
      var = klass.from_hash({ description: "API key", required: true, type: "string", default: "abc" })
      expect(var.description).to eq("API key")
      expect(var.required).to be(true)
      expect(var.type).to eq("string")
      expect(var.default).to eq("abc")
    end

    it "defaults required to false" do
      var = klass.from_hash({})
      expect(var.required).to be(false)
    end

    it "defaults type to string" do
      var = klass.from_hash({})
      expect(var.type).to eq("string")
    end

    it "allows nil default" do
      var = klass.from_hash({ description: "Optional var" })
      expect(var.default).to be_nil
    end

    it "is frozen" do
      var = klass.from_hash({ description: "Test" })
      expect(var).to be_frozen
    end
  end

  # ---------------------------------------------------------------------------
  # SwarmDocument
  # ---------------------------------------------------------------------------
  describe "SwarmDocument" do
    let(:minimal_doc) do
      described_class.new(swarm_version: "1.0", name: "Test Swarm")
    end

    it "stores swarm_version and name" do
      expect(minimal_doc.swarm_version).to eq("1.0")
      expect(minimal_doc.name).to eq("Test Swarm")
    end

    it "defaults arrays to empty frozen arrays" do
      expect(minimal_doc.agents).to eq([])
      expect(minimal_doc.agents).to be_frozen
      expect(minimal_doc.skills).to eq([])
      expect(minimal_doc.tools).to eq([])
      expect(minimal_doc.channels).to eq([])
      expect(minimal_doc.mcp_servers).to eq([])
      expect(minimal_doc.api_integrations).to eq([])
      expect(minimal_doc.tags).to eq([])
    end

    it "defaults variables to empty frozen hash" do
      expect(minimal_doc.variables).to eq({})
      expect(minimal_doc.variables).to be_frozen
    end

    it "defaults optional scalar fields to nil" do
      expect(minimal_doc.slug).to be_nil
      expect(minimal_doc.description).to be_nil
      expect(minimal_doc.author).to be_nil
      expect(minimal_doc.version).to be_nil
      expect(minimal_doc.license).to be_nil
      expect(minimal_doc.icon).to be_nil
      expect(minimal_doc.homepage).to be_nil
      expect(minimal_doc.requires).to be_nil
      expect(minimal_doc.team).to be_nil
    end

    it "is frozen" do
      expect(minimal_doc).to be_frozen
    end

    describe "count helpers" do
      let(:doc) do
        described_class.new(
          swarm_version: "1.0",
          name: "Test",
          agents:           [{ name: "A" }, { name: "B" }],
          skills:           [{ name: "s1" }],
          tools:            [{ name: "t1" }, { name: "t2" }, { name: "t3" }],
          channels:         [{ ref: "c1" }],
          mcp_servers:      [{ name: "m1" }, { name: "m2" }],
          api_integrations: [{ name: "api1" }]
        )
      end

      it "returns correct agent_count" do
        expect(doc.agent_count).to eq(2)
      end

      it "returns correct skill_count" do
        expect(doc.skill_count).to eq(1)
      end

      it "returns correct tool_count" do
        expect(doc.tool_count).to eq(3)
      end

      it "returns correct channel_count" do
        expect(doc.channel_count).to eq(1)
      end

      it "returns correct mcp_server_count" do
        expect(doc.mcp_server_count).to eq(2)
      end

      it "returns correct api_integration_count" do
        expect(doc.api_integration_count).to eq(1)
      end
    end

    it "stores nested value objects" do
      author = described_class::SwarmAuthor.from_hash({ name: "Jane" })
      requires = described_class::SwarmRequirements.from_hash({ hivemind_version: ">=2.0" })
      team = described_class::SwarmTeam.from_hash({ name: "Dream Team" })

      doc = described_class.new(
        swarm_version: "1.0",
        name: "Test",
        author: author,
        requires: requires,
        team: team
      )

      expect(doc.author.name).to eq("Jane")
      expect(doc.requires.hivemind_version).to eq(">=2.0")
      expect(doc.team.name).to eq("Dream Team")
    end
  end
end
