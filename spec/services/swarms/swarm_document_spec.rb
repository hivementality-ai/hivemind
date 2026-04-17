# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::SwarmDocument do
  describe "initialization" do
    subject(:doc) do
      described_class.new(
        swarm_version: "1.0",
        name: "Test Swarm"
      )
    end

    it "stores the version" do
      expect(doc.swarm_version).to eq("1.0")
    end

    it "stores the name" do
      expect(doc.name).to eq("Test Swarm")
    end

    it "defaults collections to empty frozen arrays" do
      expect(doc.agents).to eq([]).and be_frozen
      expect(doc.skills).to eq([]).and be_frozen
      expect(doc.tools).to eq([]).and be_frozen
      expect(doc.channels).to eq([]).and be_frozen
      expect(doc.mcp_servers).to eq([]).and be_frozen
      expect(doc.api_integrations).to eq([]).and be_frozen
      expect(doc.tags).to eq([]).and be_frozen
    end

    it "defaults variables to an empty frozen hash" do
      expect(doc.variables).to eq({}).and be_frozen
    end

    it "defaults optional fields to nil" do
      expect(doc.slug).to be_nil
      expect(doc.description).to be_nil
      expect(doc.author).to be_nil
      expect(doc.version).to be_nil
      expect(doc.license).to be_nil
      expect(doc.icon).to be_nil
      expect(doc.homepage).to be_nil
      expect(doc.requires).to be_nil
      expect(doc.team).to be_nil
    end

    it "is frozen after initialization" do
      expect(doc).to be_frozen
    end
  end

  describe "count helpers" do
    let(:doc) do
      described_class.new(
        swarm_version: "1.0",
        name: "Test Swarm",
        agents:           [{ name: "A" }, { name: "B" }],
        skills:           [{ name: "git" }],
        tools:            [{ name: "bash" }, { name: "search" }, { name: "code" }],
        api_integrations: [{ name: "pd", base_url: "https://api.pd.com" }]
      )
    end

    it "reports agent_count" do
      expect(doc.agent_count).to eq(2)
    end

    it "reports skill_count" do
      expect(doc.skill_count).to eq(1)
    end

    it "reports tool_count" do
      expect(doc.tool_count).to eq(3)
    end

    it "reports api_integration_count" do
      expect(doc.api_integration_count).to eq(1)
    end
  end

  # ------------------------------------------------------------------
  # SwarmAuthor
  # ------------------------------------------------------------------
  describe described_class::SwarmAuthor do
    describe ".from_hash" do
      context "with all fields" do
        subject(:author) do
          described_class.from_hash(
            name:  "Din Djarin",
            url:   "https://mandalorian.forge",
            email: "mando@mandalorian.forge"
          )
        end

        it "parses name" do
          expect(author.name).to eq("Din Djarin")
        end

        it "parses url" do
          expect(author.url).to eq("https://mandalorian.forge")
        end

        it "parses email" do
          expect(author.email).to eq("mando@mandalorian.forge")
        end
      end

      context "with only name" do
        subject(:author) { described_class.from_hash(name: "Din Djarin") }

        it "has nil optional fields" do
          expect(author.url).to be_nil
          expect(author.email).to be_nil
        end
      end

      context "with string keys" do
        subject(:author) { described_class.from_hash("name" => "String Keys") }

        it "handles string-keyed hashes" do
          expect(author.name).to eq("String Keys")
        end
      end
    end
  end

  # ------------------------------------------------------------------
  # SwarmRequirements
  # ------------------------------------------------------------------
  describe described_class::SwarmRequirements do
    describe ".from_hash" do
      context "with all fields" do
        subject(:req) do
          described_class.from_hash(
            hivemind_version: ">=2.0.0",
            integrations:     ["github", "slack"],
            provider_models:  ["claude-haiku-4-5"]
          )
        end

        it "parses hivemind_version" do
          expect(req.hivemind_version).to eq(">=2.0.0")
        end

        it "parses integrations" do
          expect(req.integrations).to contain_exactly("github", "slack")
        end

        it "parses provider_models" do
          expect(req.provider_models).to contain_exactly("claude-haiku-4-5")
        end
      end

      context "with empty arrays" do
        subject(:req) { described_class.from_hash({}) }

        it "defaults to empty arrays" do
          expect(req.integrations).to be_empty
          expect(req.provider_models).to be_empty
          expect(req.hivemind_version).to be_nil
        end
      end
    end
  end

  # ------------------------------------------------------------------
  # SwarmTeam
  # ------------------------------------------------------------------
  describe described_class::SwarmTeam do
    describe ".from_hash" do
      context "with all fields" do
        subject(:team) do
          described_class.from_hash(
            name:        "DevOps Squad",
            description: "CI/CD team",
            custom_soul: "## Rules\n- Be fast"
          )
        end

        it "parses name" do
          expect(team.name).to eq("DevOps Squad")
        end

        it "parses description" do
          expect(team.description).to eq("CI/CD team")
        end

        it "parses custom_soul" do
          expect(team.custom_soul).to eq("## Rules\n- Be fast")
        end
      end

      context "with minimal fields" do
        subject(:team) { described_class.from_hash(name: "Bare Team") }

        it "has nil optional fields" do
          expect(team.description).to be_nil
          expect(team.custom_soul).to be_nil
        end
      end
    end
  end

  # ------------------------------------------------------------------
  # SwarmVariable
  # ------------------------------------------------------------------
  describe described_class::SwarmVariable do
    describe ".from_hash" do
      context "with all fields" do
        subject(:var) do
          described_class.from_hash(
            description: "The API key",
            default:     "dev-key",
            required:    true,
            type:        "string"
          )
        end

        it "parses description" do
          expect(var.description).to eq("The API key")
        end

        it "parses default" do
          expect(var.default).to eq("dev-key")
        end

        it "parses required" do
          expect(var.required).to be true
        end

        it "parses type" do
          expect(var.type).to eq("string")
        end
      end

      context "with defaults" do
        subject(:var) { described_class.from_hash(description: "A var") }

        it "defaults required to false" do
          expect(var.required).to be false
        end

        it "defaults type to string" do
          expect(var.type).to eq("string")
        end

        it "has nil default" do
          expect(var.default).to be_nil
        end
      end
    end
  end
end
