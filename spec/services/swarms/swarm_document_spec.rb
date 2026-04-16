# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::SwarmDocument do
  let(:metadata) { described_class::SwarmMetadata.from_hash({ name: "Test Swarm" }) }

  describe "initialization" do
    subject(:doc) do
      described_class.new(
        swarm_version: "1.0",
        metadata: metadata
      )
    end

    it "stores the version" do
      expect(doc.swarm_version).to eq("1.0")
    end

    it "stores metadata" do
      expect(doc.metadata).to eq(metadata)
    end

    it "defaults collections to empty frozen arrays" do
      expect(doc.agents).to eq([]).and be_frozen
      expect(doc.skills).to eq([]).and be_frozen
      expect(doc.tools).to eq([]).and be_frozen
      expect(doc.channels).to eq([]).and be_frozen
      expect(doc.mcp_servers).to eq([]).and be_frozen
      expect(doc.scheduled_tasks).to eq([]).and be_frozen
      expect(doc.variables).to eq([]).and be_frozen
      expect(doc.vault_refs).to eq([]).and be_frozen
    end

    it "is frozen after initialization" do
      expect(doc).to be_frozen
    end
  end

  describe "count helpers" do
    let(:doc) do
      described_class.new(
        swarm_version: "1.0",
        metadata: metadata,
        agents: [{ name: "A" }, { name: "B" }],
        skills: [{ name: "git" }],
        tools: [{ name: "bash" }, { name: "search" }, { name: "code" }]
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
  end

  # ------------------------------------------------------------------
  # SwarmMetadata
  # ------------------------------------------------------------------
  describe described_class::SwarmMetadata do
    describe ".from_hash" do
      context "with all fields" do
        subject(:meta) do
          described_class.from_hash(
            name: "My Swarm",
            description: "Does things",
            author: "Din Djarin",
            tags: ["ai", "ruby"],
            exported_at: "2026-01-01T00:00:00Z"
          )
        end

        it "parses name" do
          expect(meta.name).to eq("My Swarm")
        end

        it "parses description" do
          expect(meta.description).to eq("Does things")
        end

        it "parses author" do
          expect(meta.author).to eq("Din Djarin")
        end

        it "parses tags as strings" do
          expect(meta.tags).to contain_exactly("ai", "ruby")
        end

        it "parses exported_at" do
          expect(meta.exported_at).to eq("2026-01-01T00:00:00Z")
        end
      end

      context "with minimal fields" do
        subject(:meta) { described_class.from_hash(name: "Bare") }

        it "has nil optional fields" do
          expect(meta.description).to be_nil
          expect(meta.author).to be_nil
          expect(meta.exported_at).to be_nil
        end

        it "has empty tags" do
          expect(meta.tags).to be_empty
        end
      end

      context "with string keys" do
        subject(:meta) { described_class.from_hash("name" => "String Keys") }

        it "handles string-keyed hashes" do
          expect(meta.name).to eq("String Keys")
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
            name: "API_KEY",
            description: "The key",
            default: "dev-key",
            required: true
          )
        end

        it "parses name" do
          expect(var.name).to eq("API_KEY")
        end

        it "parses description" do
          expect(var.description).to eq("The key")
        end

        it "parses default" do
          expect(var.default).to eq("dev-key")
        end

        it "parses required" do
          expect(var.required).to be true
        end
      end

      context "with defaults" do
        subject(:var) { described_class.from_hash(name: "DEBUG") }

        it "defaults required to false" do
          expect(var.required).to be false
        end

        it "has nil description" do
          expect(var.description).to be_nil
        end

        it "has nil default" do
          expect(var.default).to be_nil
        end
      end
    end
  end

  # ------------------------------------------------------------------
  # VaultRef
  # ------------------------------------------------------------------
  describe described_class::VaultRef do
    describe ".from_hash" do
      context "with all fields" do
        subject(:ref) { described_class.from_hash(path: "slack/bot_token", description: "Slack token") }

        it "parses path" do
          expect(ref.path).to eq("slack/bot_token")
        end

        it "parses description" do
          expect(ref.description).to eq("Slack token")
        end
      end

      context "with minimal fields" do
        subject(:ref) { described_class.from_hash(path: "openai/key") }

        it "has nil description" do
          expect(ref.description).to be_nil
        end
      end
    end
  end
end
