# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::SwarmParser do
  let(:minimal_valid_swarm) do
    {
      swarm_version: "1.0",
      metadata: { name: "Test Swarm" }
    }
  end

  let(:full_valid_swarm) do
    {
      swarm_version: "1.0",
      metadata: {
        name: "Dream Team",
        description: "A complete swarm example",
        author: "Din Djarin",
        tags: ["ai", "coding"],
        exported_at: "2026-01-01T00:00:00Z"
      },
      variables: [
        { name: "OPENAI_KEY", description: "OpenAI API key", required: true },
        { name: "DEBUG", default: "false", required: false }
      ],
      vault_refs: [
        { path: "openai/api_key", description: "OpenAI key" }
      ],
      agents: [
        {
          name: "Mando",
          role: "Senior Engineer",
          system_prompt: "You write code.",
          llm_model: "claude-sonnet-4-5",
          skills: ["git"],
          tools: ["bash"],
          mcp_servers: ["filesystem"]
        }
      ],
      skills: [
        { name: "git", content: "Git workflow instructions", summary: "Git skill", category: "coding" }
      ],
      tools: [
        { name: "bash", description: "Run bash commands", executor_type: "builtin" }
      ],
      channels: [
        { name: "general", channel_type: "slack" }
      ],
      mcp_servers: [
        { name: "filesystem", transport: "stdio", command: "npx -y @mcp/fs" }
      ],
      scheduled_tasks: [
        { name: "Daily standup", schedule: "0 9 * * *", agent: "mando", confirmation_status: "active" }
      ]
    }
  end

  describe ".call" do
    # ------------------------------------------------------------------
    # Input modes
    # ------------------------------------------------------------------
    context "when no input is provided" do
      subject(:result) { described_class.call }

      it { is_expected.not_to be_success }
      it "reports the missing input" do
        expect(result.error).to match(/path.*json.*must be provided/i)
      end
    end

    context "when parsing from a JSON string" do
      subject(:result) { described_class.call(json: minimal_valid_swarm.to_json) }

      it { is_expected.to be_success }
      it "returns a SwarmDocument" do
        expect(result.data).to be_a(Swarms::SwarmDocument)
      end
    end

    context "when parsing from a file path" do
      let(:tmp_file) do
        file = Tempfile.new(["swarm", ".json"])
        file.write(minimal_valid_swarm.to_json)
        file.close
        file
      end

      after { tmp_file.unlink }

      subject(:result) { described_class.call(path: tmp_file.path) }

      it { is_expected.to be_success }
      it "returns a SwarmDocument" do
        expect(result.data).to be_a(Swarms::SwarmDocument)
      end
    end

    # ------------------------------------------------------------------
    # File path errors
    # ------------------------------------------------------------------
    context "when the file does not exist" do
      subject(:result) { described_class.call(path: "/tmp/no_such_file_xyz.json") }

      it { is_expected.not_to be_success }
      it "reports the missing file" do
        expect(result.error).to match(/File not found/)
      end
    end

    context "when the file has a non-.json extension" do
      let(:tmp_file) do
        file = Tempfile.new(["swarm", ".txt"])
        file.write(minimal_valid_swarm.to_json)
        file.close
        file
      end

      after { tmp_file.unlink }

      subject(:result) { described_class.call(path: tmp_file.path) }

      it { is_expected.not_to be_success }
      it "reports the extension error" do
        expect(result.error).to match(/\.json extension/)
      end
    end

    # ------------------------------------------------------------------
    # JSON parsing errors
    # ------------------------------------------------------------------
    context "when the JSON is malformed" do
      subject(:result) { described_class.call(json: "{ not valid json !!!") }

      it { is_expected.not_to be_success }
      it "reports invalid JSON" do
        expect(result.error).to match(/Invalid JSON/)
      end
    end

    # ------------------------------------------------------------------
    # Schema validation errors bubble up
    # ------------------------------------------------------------------
    context "when the JSON is valid but schema is invalid" do
      let(:invalid_swarm) { { swarm_version: "1.0" } } # missing metadata

      subject(:result) { described_class.call(json: invalid_swarm.to_json) }

      it { is_expected.not_to be_success }
      it "reports the schema violation" do
        expect(result.error).to match(/Invalid .swarm.json/)
      end
    end

    # ------------------------------------------------------------------
    # SwarmDocument structure
    # ------------------------------------------------------------------
    context "with a full valid swarm" do
      subject(:result) { described_class.call(json: full_valid_swarm.to_json) }

      it { is_expected.to be_success }

      describe "the returned document" do
        let(:doc) { result.data }

        it "has the correct version" do
          expect(doc.swarm_version).to eq("1.0")
        end

        it "has metadata" do
          expect(doc.metadata).to be_a(Swarms::SwarmDocument::SwarmMetadata)
          expect(doc.metadata.name).to eq("Dream Team")
          expect(doc.metadata.author).to eq("Din Djarin")
          expect(doc.metadata.tags).to contain_exactly("ai", "coding")
        end

        it "has variables" do
          expect(doc.variables.length).to eq(2)
          expect(doc.variables.first).to be_a(Swarms::SwarmDocument::SwarmVariable)
          expect(doc.variables.first.name).to eq("OPENAI_KEY")
          expect(doc.variables.first.required).to be true
        end

        it "has vault_refs" do
          expect(doc.vault_refs.length).to eq(1)
          expect(doc.vault_refs.first).to be_a(Swarms::SwarmDocument::VaultRef)
          expect(doc.vault_refs.first.path).to eq("openai/api_key")
        end

        it "has agents" do
          expect(doc.agents.length).to eq(1)
          expect(doc.agents.first[:name]).to eq("Mando")
          expect(doc.agents.first[:skills]).to contain_exactly("git")
        end

        it "has skills" do
          expect(doc.skills.length).to eq(1)
          expect(doc.skills.first[:name]).to eq("git")
          expect(doc.skills.first[:category]).to eq("coding")
        end

        it "has tools" do
          expect(doc.tools.length).to eq(1)
          expect(doc.tools.first[:name]).to eq("bash")
        end

        it "has channels" do
          expect(doc.channels.length).to eq(1)
          expect(doc.channels.first[:channel_type]).to eq("slack")
        end

        it "has mcp_servers" do
          expect(doc.mcp_servers.length).to eq(1)
          expect(doc.mcp_servers.first[:transport]).to eq("stdio")
        end

        it "has scheduled_tasks" do
          expect(doc.scheduled_tasks.length).to eq(1)
          expect(doc.scheduled_tasks.first[:schedule]).to eq("0 9 * * *")
        end

        it "reports correct counts" do
          expect(doc.agent_count).to eq(1)
          expect(doc.skill_count).to eq(1)
          expect(doc.tool_count).to eq(1)
        end

        it "is frozen" do
          expect(doc).to be_frozen
          expect(doc.agents).to be_frozen
          expect(doc.skills).to be_frozen
        end
      end
    end

    # ------------------------------------------------------------------
    # Optional sections absent
    # ------------------------------------------------------------------
    context "with only required fields" do
      subject(:result) { described_class.call(json: minimal_valid_swarm.to_json) }

      it { is_expected.to be_success }

      describe "the returned document" do
        let(:doc) { result.data }

        it "has empty collections for optional sections" do
          expect(doc.variables).to be_empty
          expect(doc.vault_refs).to be_empty
          expect(doc.agents).to be_empty
          expect(doc.skills).to be_empty
          expect(doc.tools).to be_empty
          expect(doc.channels).to be_empty
          expect(doc.mcp_servers).to be_empty
          expect(doc.scheduled_tasks).to be_empty
        end

        it "has nil optional metadata fields" do
          expect(doc.metadata.description).to be_nil
          expect(doc.metadata.author).to be_nil
          expect(doc.metadata.tags).to be_empty
        end
      end
    end
  end
end
