# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::SwarmSchema do
  def valid_swarm(**overrides)
    {
      swarm_version: "1.0",
      name: "Test Swarm"
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
    # top-level metadata fields
    # ----------------------------------------------------------------
    describe "top-level metadata" do
      context "when name is missing" do
        let(:raw) { { swarm_version: "1.0" } }

        it { is_expected.to be_invalid }
        it "reports the missing field" do
          expect(result.errors).to include("name is required")
        end
      end

      context "when tags is not an array" do
        let(:raw) { valid_swarm(tags: "devops") }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("tags must be an array")
        end
      end

      context "with full valid top-level metadata" do
        let(:raw) do
          valid_swarm(
            name:        "Dream Team",
            slug:        "dream-team",
            description: "A swarm for dreams",
            version:     "1.2.0",
            license:     "MIT",
            tags:        ["ai", "team"],
            icon:        "🐝",
            homepage:    "https://example.com"
          )
        end

        it { is_expected.to be_valid }
      end
    end

    # ----------------------------------------------------------------
    # author
    # ----------------------------------------------------------------
    describe "author" do
      context "when author is a string instead of an object" do
        let(:raw) { valid_swarm(author: "Din Djarin") }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("author must be an object")
        end
      end

      context "when author.name is missing" do
        let(:raw) { valid_swarm(author: { url: "https://example.com" }) }

        it { is_expected.to be_invalid }
        it "reports the missing name" do
          expect(result.errors).to include("author.name is required")
        end
      end

      context "with a valid author object" do
        let(:raw) do
          valid_swarm(author: {
            name:  "Din Djarin",
            url:   "https://example.com",
            email: "mando@example.com"
          })
        end

        it { is_expected.to be_valid }
      end
    end

    # ----------------------------------------------------------------
    # requires
    # ----------------------------------------------------------------
    describe "requires" do
      context "when requires is not an object" do
        let(:raw) { valid_swarm(requires: ">=2.0.0") }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("requires must be an object")
        end
      end

      context "when integrations is not an array" do
        let(:raw) { valid_swarm(requires: { integrations: "github" }) }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("requires.integrations must be an array")
        end
      end

      context "when provider_models is not an array" do
        let(:raw) { valid_swarm(requires: { provider_models: "claude-sonnet-4" }) }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("requires.provider_models must be an array")
        end
      end

      context "with valid requires" do
        let(:raw) do
          valid_swarm(requires: {
            hivemind_version: ">=2.0.0",
            integrations:     ["github", "slack"],
            provider_models:  ["claude-haiku-4-5", "claude-sonnet-4"]
          })
        end

        it { is_expected.to be_valid }
      end
    end

    # ----------------------------------------------------------------
    # team
    # ----------------------------------------------------------------
    describe "team" do
      context "when team is not an object" do
        let(:raw) { valid_swarm(team: "DevOps Squad") }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("team must be an object")
        end
      end

      context "when team.name is missing" do
        let(:raw) { valid_swarm(team: { description: "A team" }) }

        it { is_expected.to be_invalid }
        it "reports the missing name" do
          expect(result.errors).to include("team.name is required")
        end
      end

      context "with a valid team" do
        let(:raw) do
          valid_swarm(team: {
            name:        "DevOps Squad",
            description: "CI/CD and monitoring",
            custom_soul: "## Rules\n- Be fast"
          })
        end

        it { is_expected.to be_valid }
      end
    end

    # ----------------------------------------------------------------
    # variables
    # ----------------------------------------------------------------
    describe "variables" do
      context "when not an object" do
        let(:raw) { valid_swarm(variables: [{ name: "FOO", description: "a var" }]) }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("variables must be an object")
        end
      end

      context "when a variable definition is not an object" do
        let(:raw) { valid_swarm(variables: { "MY_VAR" => "just a string" }) }

        it { is_expected.to be_invalid }
        it "reports the indexed error" do
          expect(result.errors).to include("variables.MY_VAR must be an object")
        end
      end

      context "when description is missing" do
        let(:raw) { valid_swarm(variables: { "MY_VAR" => { required: true } }) }

        it { is_expected.to be_invalid }
        it "reports the missing description" do
          expect(result.errors).to include("variables.MY_VAR.description is required")
        end
      end

      context "when required is not a boolean" do
        let(:raw) { valid_swarm(variables: { "MY_VAR" => { description: "A var", required: "yes" } }) }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("variables.MY_VAR.required must be a boolean")
        end
      end

      context "when type is invalid" do
        let(:raw) { valid_swarm(variables: { "MY_VAR" => { description: "A var", type: "uuid" } }) }

        it { is_expected.to be_invalid }
        it "reports the invalid type" do
          expect(result.errors.first).to match(/type.*invalid/)
        end
      end

      context "with valid variables hash" do
        let(:raw) do
          valid_swarm(variables: {
            "SLACK_CHANNEL_ID" => { description: "Slack channel ID", required: true, type: "string" },
            "THRESHOLD"        => { description: "Alert threshold", required: false, type: "integer", default: 10 }
          })
        end

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

      context "when thinking_visibility is invalid" do
        let(:raw) { valid_swarm(agents: [{ name: "Bob", role: "Helper", thinking_visibility: "invisible" }]) }

        it { is_expected.to be_invalid }
        it "reports the invalid value" do
          expect(result.errors.first).to match(/thinking_visibility.*invalid/)
        end
      end

      context "when thinking_budget_tokens is out of range" do
        let(:raw) { valid_swarm(agents: [{ name: "Bob", role: "Helper", thinking_budget_tokens: 999_999 }]) }

        it { is_expected.to be_invalid }
        it "reports the range error" do
          expect(result.errors.first).to match(/thinking_budget_tokens.*1 and 128000/)
        end
      end

      # --- agent channels ---

      context "when agent channels is not an array" do
        let(:raw) { valid_swarm(agents: [{ name: "Bob", role: "Helper", channels: "ops-slack" }]) }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("agents[0].channels must be an array")
        end
      end

      context "when an agent channel binding is not an object" do
        let(:raw) { valid_swarm(agents: [{ name: "Bob", role: "Helper", channels: ["ops-slack"] }]) }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("agents[0].channels[0] must be an object")
        end
      end

      context "when an agent channel binding is missing channel_ref" do
        let(:raw) { valid_swarm(agents: [{ name: "Bob", role: "Helper", channels: [{ is_default: true }] }]) }

        it { is_expected.to be_invalid }
        it "reports the missing channel_ref" do
          expect(result.errors).to include("agents[0].channels[0].channel_ref is required")
        end
      end

      context "with valid agent channel bindings" do
        let(:raw) do
          valid_swarm(agents: [{
            name: "Bob", role: "Helper",
            channels: [
              { channel_ref: "ops-slack", is_default: true },
              { channel_ref: "alerts-discord" }
            ]
          }])
        end

        it { is_expected.to be_valid }
      end

      # --- agent scheduled_tasks ---

      context "when an agent scheduled task is missing name" do
        let(:raw) do
          valid_swarm(agents: [{
            name: "Bob", role: "Helper",
            scheduled_tasks: [{ schedule: "0 9 * * *" }]
          }])
        end

        it { is_expected.to be_invalid }
        it "reports the missing name" do
          expect(result.errors).to include("agents[0].scheduled_tasks[0].name is required")
        end
      end

      context "when an agent scheduled task has an invalid cron" do
        let(:raw) do
          valid_swarm(agents: [{
            name: "Bob", role: "Helper",
            scheduled_tasks: [{ name: "Daily", schedule: "every day at 9" }]
          }])
        end

        it { is_expected.to be_invalid }
        it "reports the invalid schedule" do
          expect(result.errors.first).to match(/not a valid cron expression/)
        end
      end

      context "with valid per-agent scheduled tasks" do
        let(:raw) do
          valid_swarm(agents: [{
            name: "Watchdog", role: "DevOps Engineer",
            scheduled_tasks: [
              { name: "Health sweep", schedule: "*/15 * * * *", description: "Check health", enabled: true }
            ]
          }])
        end

        it { is_expected.to be_valid }
      end

      context "with MON-FRI named days in cron" do
        let(:raw) do
          valid_swarm(agents: [{
            name: "Commander", role: "DevOps Engineer",
            scheduled_tasks: [{ name: "Standup", schedule: "0 14 * * MON-FRI" }]
          }])
        end

        it { is_expected.to be_valid }
      end

      # --- workspace_files ---

      context "when workspace_files is not an object" do
        let(:raw) { valid_swarm(agents: [{ name: "Bob", role: "Helper", workspace_files: ["file.txt"] }]) }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("agents[0].workspace_files must be an object")
        end
      end

      context "when a workspace_files key contains path traversal" do
        let(:raw) do
          valid_swarm(agents: [{
            name: "Bob", role: "Helper",
            workspace_files: { "../../etc/passwd" => "evil" }
          }])
        end

        it { is_expected.to be_invalid }
        it "reports the traversal error" do
          expect(result.errors.first).to match(/must be a relative path without directory traversal/)
        end
      end

      context "when a workspace_files key is an absolute path" do
        let(:raw) do
          valid_swarm(agents: [{
            name: "Bob", role: "Helper",
            workspace_files: { "/etc/passwd" => "evil" }
          }])
        end

        it { is_expected.to be_invalid }
        it "reports the path error" do
          expect(result.errors.first).to match(/must be a relative path without directory traversal/)
        end
      end

      context "with valid workspace_files" do
        let(:raw) do
          valid_swarm(agents: [{
            name: "Dev", role: "Software Engineer",
            workspace_files: {
              "SOUL.md"             => "# Dev\n\nYou write code.",
              "scripts/setup.sh"    => "#!/bin/bash\nnpm install"
            }
          }])
        end

        it { is_expected.to be_valid }
      end

      context "with a fully valid agent" do
        let(:raw) do
          valid_swarm(agents: [{
            name:                    "Mando",
            role:                    "Software Engineer",
            custom_instructions:     "You write code.",
            llm_model:               "claude-sonnet-4",
            model_provider:          "anthropic",
            thinking_enabled:        true,
            thinking_budget_tokens:  16000,
            thinking_visibility:     "hidden",
            skills:                  ["git", "github"],
            tools:                   ["shell"],
            mcp_servers:             ["filesystem"],
            channels:                [{ channel_ref: "ops-slack", is_default: true }],
            scheduled_tasks:         [{ name: "Health check", schedule: "*/15 * * * *" }],
            heartbeat_enabled:       true,
            heartbeat_interval_minutes: 30,
            daily_budget_limit:      "25.0",
            monthly_budget_limit:    "500.0",
            egress_policy: {
              mode:        "allowlist",
              rules:       [{ pattern: "*.github.com" }],
              log_blocked: true
            },
            workspace_files: { "SOUL.md" => "# Mando" }
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

      context "when summary exceeds 150 characters" do
        let(:raw) { valid_swarm(skills: [{ name: "git", content: "X", summary: "A" * 151 }]) }

        it { is_expected.to be_invalid }
        it "reports the length error" do
          expect(result.errors).to include("skills[0].summary exceeds 150 character limit")
        end
      end

      context "when content exceeds 100KB" do
        let(:raw) { valid_swarm(skills: [{ name: "git", summary: "Git", content: "X" * (100 * 1024 + 1) }]) }

        it { is_expected.to be_invalid }
        it "reports the size error" do
          expect(result.errors).to include("skills[0].content exceeds 100KB limit")
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

      context "with skill tools array containing a non-string" do
        let(:raw) { valid_swarm(skills: [{ name: "git", content: "X", summary: "Git", tools: [123] }]) }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("skills[0].tools[0] must be a string")
        end
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
            name:            "my_tool",
            description:     "Does a thing",
            executor_type:   "custom_script",
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
      context "when ref is missing" do
        let(:raw) { valid_swarm(channels: [{ name: "general", channel_type: "slack" }]) }

        it { is_expected.to be_invalid }
        it "reports the missing ref" do
          expect(result.errors).to include("channels[0].ref is required")
        end
      end

      context "when name is missing" do
        let(:raw) { valid_swarm(channels: [{ ref: "ops-slack", channel_type: "slack" }]) }

        it { is_expected.to be_invalid }
        it "reports the missing name" do
          expect(result.errors).to include("channels[0].name is required")
        end
      end

      context "when channel_type is missing" do
        let(:raw) { valid_swarm(channels: [{ ref: "ops-slack", name: "Ops Slack" }]) }

        it { is_expected.to be_invalid }
        it "reports the missing channel_type" do
          expect(result.errors).to include("channels[0].channel_type is required")
        end
      end

      context "when channel_type is invalid" do
        let(:raw) { valid_swarm(channels: [{ ref: "ops-fax", name: "Ops Fax", channel_type: "fax" }]) }

        it { is_expected.to be_invalid }
        it "reports the invalid channel_type" do
          expect(result.errors.first).to match(/channel_type.*invalid/)
        end
      end

      context "with a valid slack channel" do
        let(:raw) { valid_swarm(channels: [{ ref: "ops-slack", name: "Ops Slack", channel_type: "slack" }]) }

        it { is_expected.to be_valid }
      end

      context "with all valid channel types" do
        %w[slack discord telegram whatsapp signal web].each do |type|
          it "accepts #{type}" do
            raw = valid_swarm(channels: [{ ref: "ch-#{type}", name: type.capitalize, channel_type: type }])
            expect(described_class.validate(raw)).to be_valid
          end
        end
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

      context "when auth_config is not an object" do
        let(:raw) { valid_swarm(mcp_servers: [{ name: "remote", transport: "sse", url: "https://mcp.example.com", auth_config: "Bearer token" }]) }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("mcp_servers[0].auth_config must be an object")
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
    # api_integrations
    # ----------------------------------------------------------------
    describe "api_integrations" do
      context "when not an array" do
        let(:raw) { valid_swarm(api_integrations: { name: "pagerduty", base_url: "https://api.pagerduty.com" }) }

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("api_integrations must be an array")
        end
      end

      context "when name is missing" do
        let(:raw) { valid_swarm(api_integrations: [{ base_url: "https://api.example.com" }]) }

        it { is_expected.to be_invalid }
        it "reports the missing name" do
          expect(result.errors).to include("api_integrations[0].name is required")
        end
      end

      context "when base_url is missing" do
        let(:raw) { valid_swarm(api_integrations: [{ name: "pagerduty" }]) }

        it { is_expected.to be_invalid }
        it "reports the missing base_url" do
          expect(result.errors).to include("api_integrations[0].base_url is required")
        end
      end

      context "when endpoints is not an array" do
        let(:raw) do
          valid_swarm(api_integrations: [{
            name: "pd", base_url: "https://api.pd.com",
            endpoints: "GET /incidents"
          }])
        end

        it { is_expected.to be_invalid }
        it "reports the type error" do
          expect(result.errors).to include("api_integrations[0].endpoints must be an array")
        end
      end

      context "when an endpoint is missing method" do
        let(:raw) do
          valid_swarm(api_integrations: [{
            name: "pd", base_url: "https://api.pd.com",
            endpoints: [{ path: "/incidents" }]
          }])
        end

        it { is_expected.to be_invalid }
        it "reports the missing method" do
          expect(result.errors).to include("api_integrations[0].endpoints[0].method is required")
        end
      end

      context "when timeout_seconds is not a positive integer" do
        let(:raw) do
          valid_swarm(api_integrations: [{
            name: "pd", base_url: "https://api.pd.com",
            timeout_seconds: 0
          }])
        end

        it { is_expected.to be_invalid }
        it "reports the validation error" do
          expect(result.errors).to include("api_integrations[0].timeout_seconds must be a positive integer")
        end
      end

      context "with a valid api integration" do
        let(:raw) do
          valid_swarm(api_integrations: [{
            name:            "pagerduty",
            description:     "PagerDuty API",
            base_url:        "https://api.pagerduty.com",
            timeout_seconds: 30,
            endpoints:       [{ method: "GET", path: "/incidents", description: "List incidents" }]
          }])
        end

        it { is_expected.to be_valid }
      end

      context "with an empty api_integrations array" do
        let(:raw) { valid_swarm(api_integrations: []) }

        it { is_expected.to be_valid }
      end
    end

    # ----------------------------------------------------------------
    # Full spec example validation
    # ----------------------------------------------------------------
    describe "spec example" do
      context "with the DevOps swarm example" do
        let(:raw) do
          {
            swarm_version: "1.0",
            name:          "DevOps Swarm",
            slug:          "devops-swarm",
            description:   "3-agent DevOps team",
            version:       "1.0.0",
            author:        { name: "Hivemind Community", url: "https://hivemind.dev" },
            tags:          ["devops", "cicd"],

            requires: {
              hivemind_version: ">=2.0.0",
              integrations:     ["github", "slack"],
              provider_models:  ["claude-haiku-4-5", "claude-sonnet-4"]
            },

            variables: {
              "SLACK_CHANNEL_ID" => { description: "Slack channel for alerts", required: true, type: "string" },
              "GITHUB_ORG"       => { description: "GitHub org", required: true, type: "string" }
            },

            team: {
              name:        "DevOps Squadron",
              description: "CI/CD, monitoring, incident response"
            },

            skills: [{
              name:     "incident_triage",
              summary:  "Classify and triage production incidents",
              category: "automation",
              content:  "# Incident Triage\n\n## Severity Levels"
            }],

            tools: [{
              name:            "service_health",
              description:     "Check health of a service",
              executor_type:   "custom_script",
              script_template: "curl -sf https://{{service}}.example.com/health"
            }],

            channels: [{
              ref:          "ops-slack",
              name:         "DevOps Slack",
              channel_type: "slack"
            }],

            mcp_servers: [{
              name:      "github-mcp",
              transport: "stdio",
              command:   "npx -y @modelcontextprotocol/server-github",
              env_vars:  { "GITHUB_PERSONAL_ACCESS_TOKEN" => "vault:github/pat" }
            }],

            api_integrations: [],

            agents: [
              {
                name:  "Commander",
                role:  "DevOps Engineer",
                tools: ["shell", "service_health"],
                skills: ["incident_triage"],
                channels: [{ channel_ref: "ops-slack", is_default: true }],
                mcp_servers: ["github-mcp"],
                scheduled_tasks: [{
                  name:     "Morning Status",
                  schedule: "0 14 * * 1-5"
                }],
                heartbeat_enabled:          true,
                heartbeat_interval_minutes: 60,
                daily_budget_limit:         "25.0",
                egress_policy: {
                  mode:  "allowlist",
                  rules: [{ pattern: "*.github.com" }]
                }
              },
              {
                name:  "Watchdog",
                role:  "DevOps Engineer",
                tools: ["shell", "service_health"],
                scheduled_tasks: [{
                  name:     "Health Sweep",
                  schedule: "*/15 * * * *"
                }]
              }
            ]
          }
        end

        it { is_expected.to be_valid }
        it "has no errors" do
          expect(result.errors).to be_empty
        end
      end
    end

    # ----------------------------------------------------------------
    # Error accumulation
    # ----------------------------------------------------------------
    describe "error accumulation" do
      context "with multiple invalid sections" do
        let(:raw) do
          {
            swarm_version: "1.0",
            name:          "Multi Error Swarm",
            agents:        [{ name: "Bob" }, { role: "Helper" }],
            skills:        [{ name: "git" }],
            mcp_servers:   [{ name: "fs", transport: "stdio" }]
          }
        end

        it "collects all errors without short-circuiting" do
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
