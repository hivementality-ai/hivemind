# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::SwarmSchema do
  def valid_swarm(**overrides)
    {
      swarm_version: "1.0",
      metadata: { name: "Test Swarm" }
    }.merge(overrides)
  end

  describe ".validate" do
    subject(:result) { described_class.validate(raw) }

    context "with a minimal valid document" do
      let(:raw) { valid_swarm }

      it { is_expected.to be_valid }
      it "has no errors" do
        expect(result.errors).to be_empty
      end
    end

    # ----------------------------------------------------------------
    # swarm_version
    # ----------------------------------------------------------------
    describe "swarm_version" do
      context "when missing" do
        let(:raw) { valid_swarm.except(:swarm_version) }

        it { is_expected.to be_invalid }
        it "reports the missing field" do
          expect(result.errors).to include("swarm_version is required")
        end
      end

      context "when unsupported" do
        let(:raw) { valid_swarm(swarm_version: "9.9") }

        it { is_expected.to be_invalid }
        it "reports the unsupported version" do
          expect(result.errors.first).to match(/not supported/)
        end
      end

      context "when valid" do
        let(:raw) { valid_swarm(swarm_version: "1.0") }

        it { is_expected.to be_valid }
      end
    end

    # ----------------------------------------------------------------
    # metadata
    # ----------------------------------------------------------------
    describe "metadata" do
      context "when missing" do
        let(:raw) { { swarm_version: "1.0" } }

        it { is_expected.to be_invalid }
        it "reports the missing field" do
          expect(result.errors).to include("metadata is required")
        end
      end

      context "when not a hash" do
        let(:raw) { valid_swarm(metadata: "bad") }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("metadata must be an object")
        end
      end

      context "when name is missing" do
        let(:raw) { valid_swarm(metadata: { description: "no name here" }) }

        it { is_expected.to be_invalid }
        it "reports the missing name" do
          expect(result.errors).to include("metadata.name is required")
        end
      end

      context "when tags is not an array" do
        let(:raw) { valid_swarm(metadata: { name: "Swarm", tags: "tag1" }) }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("metadata.tags must be an array")
        end
      end

      context "with full valid metadata" do
        let(:raw) do
          valid_swarm(metadata: {
            name: "Dream Team",
            description: "A swarm for dreams",
            author: "Din Djarin",
            tags: ["ai", "team"],
            exported_at: "2026-01-01T00:00:00Z"
          })
        end

        it { is_expected.to be_valid }
      end
    end

    # ----------------------------------------------------------------
    # variables
    # ----------------------------------------------------------------
    describe "variables" do
      context "when not an array" do
        let(:raw) { valid_swarm(variables: "bad") }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("variables must be an array")
        end
      end

      context "when an element has no name" do
        let(:raw) { valid_swarm(variables: [{ description: "no name" }]) }

        it { is_expected.to be_invalid }
        it "reports the indexed error" do
          expect(result.errors).to include("variables[0].name is required")
        end
      end

      context "when required is not a boolean" do
        let(:raw) { valid_swarm(variables: [{ name: "MY_VAR", required: "yes" }]) }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("variables[0].required must be a boolean")
        end
      end

      context "with valid variables" do
        let(:raw) do
          valid_swarm(variables: [
            { name: "API_KEY", description: "The API key", required: true },
            { name: "DEBUG", default: "false", required: false }
          ])
        end

        it { is_expected.to be_valid }
      end
    end

    # ----------------------------------------------------------------
    # vault_refs
    # ----------------------------------------------------------------
    describe "vault_refs" do
      context "when path is missing" do
        let(:raw) { valid_swarm(vault_refs: [{ description: "no path" }]) }

        it { is_expected.to be_invalid }
        it "reports the missing path" do
          expect(result.errors).to include("vault_refs[0].path is required")
        end
      end

      context "when path lacks namespace/key format" do
        let(:raw) { valid_swarm(vault_refs: [{ path: "nodivider" }]) }

        it { is_expected.to be_invalid }
        it "reports the format error" do
          expect(result.errors.first).to match(/namespace\/key format/)
        end
      end

      context "with valid vault_refs" do
        let(:raw) { valid_swarm(vault_refs: [{ path: "slack/bot_token", description: "Slack token" }]) }

        it { is_expected.to be_valid }
      end
    end

    # ----------------------------------------------------------------
    # agents
    # ----------------------------------------------------------------
    describe "agents" do
      context "when not an array" do
        let(:raw) { valid_swarm(agents: { name: "Bob" }) }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("agents must be an array")
        end
      end

      context "when an agent has no name" do
        let(:raw) { valid_swarm(agents: [{ role: "Helper" }]) }

        it { is_expected.to be_invalid }
        it "reports the indexed error" do
          expect(result.errors).to include("agents[0].name is required")
        end
      end

      context "when an agent has no role" do
        let(:raw) { valid_swarm(agents: [{ name: "Bob" }]) }

        it { is_expected.to be_invalid }
        it "reports the indexed error" do
          expect(result.errors).to include("agents[0].role is required")
        end
      end

      context "with an invalid egress policy mode" do
        let(:raw) do
          valid_swarm(agents: [{
            name: "Bob", role: "Helper",
            egress_policy: { mode: "banana" }
          }])
        end

        it { is_expected.to be_invalid }
        it "reports the egress policy error" do
          expect(result.errors.first).to match(/egress_policy.*mode.*invalid/)
        end
      end

      context "when agent skills list contains a non-string" do
        let(:raw) { valid_swarm(agents: [{ name: "Bob", role: "Helper", skills: [123] }]) }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("agents[0].skills[0] must be a string reference")
        end
      end

      context "with a fully valid agent" do
        let(:raw) do
          valid_swarm(agents: [{
            name: "Mando",
            role: "Senior Engineer",
            system_prompt: "You write code.",
            llm_model: "claude-sonnet-4-5",
            model_provider: "anthropic",
            skills: ["git", "github"],
            tools: ["bash"],
            mcp_servers: ["filesystem"],
            egress_policy: {
              mode: "allowlist",
              rules: [{ pattern: "github.com" }],
              log_blocked: true
            }
          }])
        end

        it { is_expected.to be_valid }
      end
    end

    # ----------------------------------------------------------------
    # skills
    # ----------------------------------------------------------------
    describe "skills" do
      context "when a skill has no name" do
        let(:raw) { valid_swarm(skills: [{ content: "Do stuff", summary: "Does stuff" }]) }

        it { is_expected.to be_invalid }
        it "reports the missing name" do
          expect(result.errors).to include("skills[0].name is required")
        end
      end

      context "when a skill has no content" do
        let(:raw) { valid_swarm(skills: [{ name: "git", summary: "Git skill" }]) }

        it { is_expected.to be_invalid }
        it "reports the missing content" do
          expect(result.errors).to include("skills[0].content is required")
        end
      end

      context "when a skill has no summary" do
        let(:raw) { valid_swarm(skills: [{ name: "git", content: "Git instructions" }]) }

        it { is_expected.to be_invalid }
        it "reports the missing summary" do
          expect(result.errors).to include("skills[0].summary is required")
        end
      end

      context "when category is invalid" do
        let(:raw) { valid_swarm(skills: [{ name: "git", content: "Git instructions", summary: "Git", category: "wizardry" }]) }

        it { is_expected.to be_invalid }
        it "reports the invalid category" do
          expect(result.errors.first).to match(/category.*invalid/)
        end
      end

      context "with a valid skill" do
        let(:raw) { valid_swarm(skills: [{ name: "git", content: "Git instructions", summary: "Git workflow", category: "coding" }]) }

        it { is_expected.to be_valid }
      end
    end

    # ----------------------------------------------------------------
    # tools
    # ----------------------------------------------------------------
    describe "tools" do
      context "when a tool has no name" do
        let(:raw) { valid_swarm(tools: [{ description: "A tool", executor_type: "builtin" }]) }

        it { is_expected.to be_invalid }
      end

      context "when a tool has no executor_type" do
        let(:raw) { valid_swarm(tools: [{ name: "bash", description: "Bash tool" }]) }

        it { is_expected.to be_invalid }
        it "reports the missing executor_type" do
          expect(result.errors).to include("tools[0].executor_type is required")
        end
      end

      context "when executor_type is custom_script but script_template is missing" do
        let(:raw) { valid_swarm(tools: [{ name: "my_tool", description: "Custom", executor_type: "custom_script" }]) }

        it { is_expected.to be_invalid }
        it "reports the missing script_template" do
          expect(result.errors).to include("tools[0].script_template is required when executor_type is 'custom_script'")
        end
      end

      context "with a valid custom_script tool" do
        let(:raw) do
          valid_swarm(tools: [{
            name: "my_tool",
            description: "Does a thing",
            executor_type: "custom_script",
            script_template: "echo {{message}}"
          }])
        end

        it { is_expected.to be_valid }
      end
    end

    # ----------------------------------------------------------------
    # channels
    # ----------------------------------------------------------------
    describe "channels" do
      context "when channel_type is missing" do
        let(:raw) { valid_swarm(channels: [{ name: "general" }]) }

        it { is_expected.to be_invalid }
        it "reports the missing channel_type" do
          expect(result.errors).to include("channels[0].channel_type is required")
        end
      end

      context "when channel_type is invalid" do
        let(:raw) { valid_swarm(channels: [{ name: "general", channel_type: "fax" }]) }

        it { is_expected.to be_invalid }
        it "reports the invalid channel_type" do
          expect(result.errors.first).to match(/channel_type.*invalid/)
        end
      end

      context "with a valid slack channel" do
        let(:raw) { valid_swarm(channels: [{ name: "general", channel_type: "slack" }]) }

        it { is_expected.to be_valid }
      end
    end

    # ----------------------------------------------------------------
    # mcp_servers
    # ----------------------------------------------------------------
    describe "mcp_servers" do
      context "when transport is missing" do
        let(:raw) { valid_swarm(mcp_servers: [{ name: "filesystem" }]) }

        it { is_expected.to be_invalid }
        it "reports the missing transport" do
          expect(result.errors).to include("mcp_servers[0].transport is required")
        end
      end

      context "when transport is invalid" do
        let(:raw) { valid_swarm(mcp_servers: [{ name: "fs", transport: "http" }]) }

        it { is_expected.to be_invalid }
        it "reports the invalid transport" do
          expect(result.errors.first).to match(/transport.*invalid/)
        end
      end

      context "when stdio transport is missing command" do
        let(:raw) { valid_swarm(mcp_servers: [{ name: "fs", transport: "stdio" }]) }

        it { is_expected.to be_invalid }
        it "reports the missing command" do
          expect(result.errors).to include("mcp_servers[0].command is required for stdio transport")
        end
      end

      context "when sse transport is missing url" do
        let(:raw) { valid_swarm(mcp_servers: [{ name: "remote", transport: "sse" }]) }

        it { is_expected.to be_invalid }
        it "reports the missing url" do
          expect(result.errors).to include("mcp_servers[0].url is required for sse transport")
        end
      end

      context "when env_vars is not an object" do
        let(:raw) { valid_swarm(mcp_servers: [{ name: "fs", transport: "stdio", command: "npx mcp", env_vars: "bad" }]) }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("mcp_servers[0].env_vars must be an object")
        end
      end

      context "with a valid stdio server" do
        let(:raw) { valid_swarm(mcp_servers: [{ name: "filesystem", transport: "stdio", command: "npx -y @mcp/fs" }]) }

        it { is_expected.to be_valid }
      end

      context "with a valid sse server" do
        let(:raw) { valid_swarm(mcp_servers: [{ name: "remote", transport: "sse", url: "https://mcp.example.com" }]) }

        it { is_expected.to be_valid }
      end
    end

    # ----------------------------------------------------------------
    # scheduled_tasks
    # ----------------------------------------------------------------
    describe "scheduled_tasks" do
      context "when agent reference is missing" do
        let(:raw) { valid_swarm(scheduled_tasks: [{ name: "Daily", schedule: "0 9 * * *" }]) }

        it { is_expected.to be_invalid }
        it "reports the missing agent" do
          expect(result.errors).to include("scheduled_tasks[0].agent is required")
        end
      end

      context "when schedule is not a valid cron expression" do
        let(:raw) { valid_swarm(scheduled_tasks: [{ name: "Daily", schedule: "every day", agent: "mando" }]) }

        it { is_expected.to be_invalid }
        it "reports the invalid schedule" do
          expect(result.errors.first).to match(/not a valid cron expression/)
        end
      end

      context "when confirmation_status is invalid" do
        let(:raw) { valid_swarm(scheduled_tasks: [{ name: "Daily", schedule: "0 9 * * *", agent: "mando", confirmation_status: "maybe" }]) }

        it { is_expected.to be_invalid }
        it "reports the invalid status" do
          expect(result.errors.first).to match(/confirmation_status.*invalid/)
        end
      end

      context "with a valid scheduled task" do
        let(:raw) { valid_swarm(scheduled_tasks: [{ name: "Daily standup", schedule: "0 9 * * *", agent: "mando", confirmation_status: "active" }]) }

        it { is_expected.to be_valid }
      end
    end

    # ----------------------------------------------------------------
    # Multiple errors
    # ----------------------------------------------------------------
    describe "error accumulation" do
      context "with multiple invalid sections" do
        let(:raw) do
          {
            swarm_version: "1.0",
            metadata: { name: "Multi Error Swarm" },
            agents: [{ name: "Bob" }, { role: "Helper" }],
            skills: [{ name: "git" }],
            mcp_servers: [{ name: "fs", transport: "stdio" }]
          }
        end

        it "collects all errors" do
          expect(result.errors.length).to be >= 4
          expect(result.errors).to include("agents[0].role is required")
          expect(result.errors).to include("agents[1].name is required")
          expect(result.errors).to include("skills[0].content is required")
          expect(result.errors).to include("mcp_servers[0].command is required for stdio transport")
        end
      end
    end
  end
end
