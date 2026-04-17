# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::SwarmParser do
  let(:minimal_valid_swarm) do
    {
      swarm_version: "1.0",
      name:          "Test Swarm"
    }
  end

  let(:full_valid_swarm) do
    {
      swarm_version: "1.0",
      name:          "Dream Team",
      slug:          "dream-team",
      description:   "A complete swarm example",
      version:       "1.0.0",
      license:       "MIT",
      tags:          ["ai", "coding"],
      icon:          "🐝",
      homepage:      "https://example.com",
      author: {
        name:  "Din Djarin",
        url:   "https://mandalorian.forge",
        email: "mando@mandalorian.forge"
      },
      requires: {
        hivemind_version: ">=2.0.0",
        integrations:     ["github"],
        provider_models:  ["claude-sonnet-4"]
      },
      team: {
        name:        "Dream Team",
        description: "A dream team",
        custom_soul: "## Rules\n- Be excellent"
      },
      variables: {
        "OPENAI_KEY" => { description: "OpenAI API key", required: true, type: "string" },
        "DEBUG"      => { description: "Debug mode", required: false, type: "boolean", default: false }
      },
      agents: [
        {
          name:     "Mando",
          role:     "Software Engineer",
          llm_model: "claude-sonnet-4",
          skills:   ["git"],
          tools:    ["shell"],
          mcp_servers: ["filesystem"],
          channels: [{ channel_ref: "ops-slack", is_default: true }],
          scheduled_tasks: [{ name: "Health check", schedule: "*/15 * * * *" }]
        }
      ],
      skills: [
        { name: "git", content: "Git workflow instructions", summary: "Git skill", category: "coding" }
      ],
      tools: [
        { name: "custom_bash", description: "Run bash commands", executor_type: "custom_script", script_template: "bash -c {{cmd}}" }
      ],
      channels: [
        { ref: "ops-slack", name: "Ops Slack", channel_type: "slack" }
      ],
      mcp_servers: [
        { name: "filesystem", transport: "stdio", command: "npx -y @mcp/fs" }
      ],
      api_integrations: [
        { name: "pagerduty", base_url: "https://api.pagerduty.com", description: "PD API" }
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

    context "when file exceeds 5MB" do
      let(:tmp_file) do
        file = Tempfile.new(["swarm", ".json"])
        file.write("x" * (5 * 1024 * 1024 + 1))
        file.close
        file
      end

      after { tmp_file.unlink }

      subject(:result) { described_class.call(path: tmp_file.path) }

      it { is_expected.not_to be_success }
      it "reports the size error" do
        expect(result.error).to match(/5 MB/)
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
      let(:invalid_swarm) { { swarm_version: "1.0" } } # missing name

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

        it "has flat top-level metadata fields" do
          expect(doc.name).to eq("Dream Team")
          expect(doc.slug).to eq("dream-team")
          expect(doc.description).to eq("A complete swarm example")
          expect(doc.version).to eq("1.0.0")
          expect(doc.license).to eq("MIT")
          expect(doc.icon).to eq("🐝")
          expect(doc.homepage).to eq("https://example.com")
          expect(doc.tags).to contain_exactly("ai", "coding")
        end

        it "has a typed author object" do
          expect(doc.author).to be_a(Swarms::SwarmDocument::SwarmAuthor)
          expect(doc.author.name).to eq("Din Djarin")
          expect(doc.author.url).to eq("https://mandalorian.forge")
        end

        it "has a typed requires object" do
          expect(doc.requires).to be_a(Swarms::SwarmDocument::SwarmRequirements)
          expect(doc.requires.hivemind_version).to eq(">=2.0.0")
          expect(doc.requires.integrations).to contain_exactly("github")
        end

        it "has a typed team object" do
          expect(doc.team).to be_a(Swarms::SwarmDocument::SwarmTeam)
          expect(doc.team.name).to eq("Dream Team")
        end

        it "has variables as a hash keyed by name" do
          expect(doc.variables).to be_a(Hash)
          expect(doc.variables.keys).to contain_exactly("OPENAI_KEY", "DEBUG")
          expect(doc.variables["OPENAI_KEY"]).to be_a(Swarms::SwarmDocument::SwarmVariable)
          expect(doc.variables["OPENAI_KEY"].required).to be true
          expect(doc.variables["DEBUG"].type).to eq("boolean")
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
          expect(doc.tools.first[:name]).to eq("custom_bash")
        end

        it "has channels" do
          expect(doc.channels.length).to eq(1)
          expect(doc.channels.first[:ref]).to eq("ops-slack")
          expect(doc.channels.first[:channel_type]).to eq("slack")
        end

        it "has mcp_servers" do
          expect(doc.mcp_servers.length).to eq(1)
          expect(doc.mcp_servers.first[:transport]).to eq("stdio")
        end

        it "has api_integrations" do
          expect(doc.api_integrations.length).to eq(1)
          expect(doc.api_integrations.first[:name]).to eq("pagerduty")
        end

        it "reports correct counts" do
          expect(doc.agent_count).to eq(1)
          expect(doc.skill_count).to eq(1)
          expect(doc.tool_count).to eq(1)
          expect(doc.api_integration_count).to eq(1)
        end

        it "is frozen" do
          expect(doc).to be_frozen
          expect(doc.agents).to be_frozen
          expect(doc.skills).to be_frozen
          expect(doc.variables).to be_frozen
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

        it "has empty collections for optional array sections" do
          expect(doc.agents).to be_empty
          expect(doc.skills).to be_empty
          expect(doc.tools).to be_empty
          expect(doc.channels).to be_empty
          expect(doc.mcp_servers).to be_empty
          expect(doc.api_integrations).to be_empty
          expect(doc.tags).to be_empty
        end

        it "has empty hash for variables" do
          expect(doc.variables).to eq({})
        end

        it "has nil optional top-level fields" do
          expect(doc.slug).to be_nil
          expect(doc.description).to be_nil
          expect(doc.author).to be_nil
          expect(doc.version).to be_nil
          expect(doc.license).to be_nil
          expect(doc.requires).to be_nil
          expect(doc.team).to be_nil
        end
      end
    end
  end
end
