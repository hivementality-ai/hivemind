# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::SwarmSchema do
  subject(:schema) { described_class.new }

  def valid_swarm(**overrides)
    {
      swarm_version: "1.0",
      name: "Test Swarm",
      agents: [{ name: "Mando", role: "Software Engineer" }]
    }.deep_merge(overrides)
  end

  def validate(data)
    schema.validate(data)
  end

  # ---------------------------------------------------------------------------
  # ValidationResult
  # ---------------------------------------------------------------------------
  describe "ValidationResult" do
    it "is valid when errors are empty" do
      result = Swarms::SwarmSchema::ValidationResult.new(errors: [])
      expect(result).to be_valid
      expect(result).not_to be_invalid
    end

    it "is invalid when errors are present" do
      result = Swarms::SwarmSchema::ValidationResult.new(errors: ["something wrong"])
      expect(result).to be_invalid
      expect(result).not_to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Version
  # ---------------------------------------------------------------------------
  describe "version validation" do
    it "accepts a supported version" do
      expect(validate(valid_swarm)).to be_valid
    end

    it "requires swarm_version" do
      result = validate(valid_swarm.except(:swarm_version))
      expect(result).to be_invalid
      expect(result.errors).to include("swarm_version is required")
    end

    it "rejects an unsupported version" do
      result = validate(valid_swarm(swarm_version: "99.0"))
      expect(result).to be_invalid
      expect(result.errors).to include(match(/unsupported swarm_version/))
    end
  end

  # ---------------------------------------------------------------------------
  # Top-level metadata
  # ---------------------------------------------------------------------------
  describe "top-level metadata" do
    it "requires name" do
      result = validate(valid_swarm.except(:name))
      expect(result).to be_invalid
      expect(result.errors).to include("name is required")
    end

    it "rejects blank name" do
      result = validate(valid_swarm(name: ""))
      expect(result).to be_invalid
      expect(result.errors).to include("name is required")
    end

    it "rejects non-string name" do
      result = validate(valid_swarm(name: 123))
      expect(result).to be_invalid
      expect(result.errors).to include("name must be a string")
    end

    it "rejects slug with spaces" do
      result = validate(valid_swarm(slug: "my slug"))
      expect(result).to be_invalid
      expect(result.errors).to include(match(/slug must be/))
    end

    it "accepts valid slug" do
      result = validate(valid_swarm(slug: "my-slug_123"))
      expect(result).to be_valid
    end

    it "rejects non-string description" do
      result = validate(valid_swarm(description: 42))
      expect(result).to be_invalid
      expect(result.errors).to include("description must be a string")
    end

    it "rejects non-string version" do
      result = validate(valid_swarm(version: true))
      expect(result).to be_invalid
      expect(result.errors).to include("version must be a string")
    end

    it "rejects non-string license" do
      result = validate(valid_swarm(license: []))
      expect(result).to be_invalid
      expect(result.errors).to include("license must be a string")
    end

    it "rejects non-array tags" do
      result = validate(valid_swarm(tags: "ruby"))
      expect(result).to be_invalid
      expect(result.errors).to include("tags must be an array")
    end

    it "accepts array of string tags" do
      result = validate(valid_swarm(tags: %w[ruby rails]))
      expect(result).to be_valid
    end

    it "rejects non-string tag items" do
      result = validate(valid_swarm(tags: [1, 2]))
      expect(result).to be_invalid
      expect(result.errors).to include(match(/tags\[0\] must be a string/))
    end

    it "rejects non-string icon" do
      result = validate(valid_swarm(icon: 99))
      expect(result).to be_invalid
      expect(result.errors).to include("icon must be a string")
    end

    it "rejects non-string homepage" do
      result = validate(valid_swarm(homepage: {}))
      expect(result).to be_invalid
      expect(result.errors).to include("homepage must be a string")
    end
  end

  # ---------------------------------------------------------------------------
  # Author
  # ---------------------------------------------------------------------------
  describe "author validation" do
    it "is optional" do
      result = validate(valid_swarm)
      expect(result).to be_valid
    end

    it "rejects non-hash author" do
      result = validate(valid_swarm(author: "Jane"))
      expect(result).to be_invalid
      expect(result.errors).to include("author must be an object")
    end

    it "requires author.name when author is present" do
      result = validate(valid_swarm(author: { url: "https://example.com" }))
      expect(result).to be_invalid
      expect(result.errors).to include("author.name is required")
    end

    it "accepts valid author" do
      result = validate(valid_swarm(author: { name: "Jane", url: "https://jane.dev", email: "jane@dev.io" }))
      expect(result).to be_valid
    end

    it "rejects non-string author.url" do
      result = validate(valid_swarm(author: { name: "Jane", url: 42 }))
      expect(result).to be_invalid
      expect(result.errors).to include("author.url must be a string")
    end

    it "rejects non-string author.email" do
      result = validate(valid_swarm(author: { name: "Jane", email: false }))
      expect(result).to be_invalid
      expect(result.errors).to include("author.email must be a string")
    end
  end

  # ---------------------------------------------------------------------------
  # Requires
  # ---------------------------------------------------------------------------
  describe "requires validation" do
    it "is optional" do
      result = validate(valid_swarm)
      expect(result).to be_valid
    end

    it "rejects non-hash requires" do
      result = validate(valid_swarm(requires: "latest"))
      expect(result).to be_invalid
      expect(result.errors).to include("requires must be an object")
    end

    it "rejects non-string hivemind_version" do
      result = validate(valid_swarm(requires: { hivemind_version: 1 }))
      expect(result).to be_invalid
      expect(result.errors).to include("requires.hivemind_version must be a string")
    end

    it "rejects non-array integrations" do
      result = validate(valid_swarm(requires: { integrations: "github" }))
      expect(result).to be_invalid
      expect(result.errors).to include("requires.integrations must be an array")
    end

    it "rejects non-array provider_models" do
      result = validate(valid_swarm(requires: { provider_models: "claude" }))
      expect(result).to be_invalid
      expect(result.errors).to include("requires.provider_models must be an array")
    end

    it "accepts valid requires" do
      result = validate(valid_swarm(requires: {
        hivemind_version: ">=2.0",
        integrations: ["github"],
        provider_models: ["claude-3-5-sonnet"]
      }))
      expect(result).to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Team
  # ---------------------------------------------------------------------------
  describe "team validation" do
    it "is optional" do
      result = validate(valid_swarm)
      expect(result).to be_valid
    end

    it "rejects non-hash team" do
      result = validate(valid_swarm(team: "my team"))
      expect(result).to be_invalid
      expect(result.errors).to include("team must be an object")
    end

    it "rejects non-string team.name" do
      result = validate(valid_swarm(team: { name: 123 }))
      expect(result).to be_invalid
      expect(result.errors).to include("team.name must be a string")
    end

    it "rejects non-string team.description" do
      result = validate(valid_swarm(team: { description: [] }))
      expect(result).to be_invalid
      expect(result.errors).to include("team.description must be a string")
    end

    it "accepts valid team" do
      result = validate(valid_swarm(team: { name: "Dream Team", description: "Best team" }))
      expect(result).to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Variables
  # ---------------------------------------------------------------------------
  describe "variables validation" do
    it "is optional" do
      result = validate(valid_swarm)
      expect(result).to be_valid
    end

    it "rejects non-hash variables" do
      result = validate(valid_swarm(variables: ["VAR"]))
      expect(result).to be_invalid
      expect(result.errors).to include("variables must be an object")
    end

    it "rejects non-object variable definition" do
      result = validate(valid_swarm(variables: { "MY_VAR" => "some string" }))
      expect(result).to be_invalid
      expect(result.errors).to include("variables.MY_VAR must be an object")
    end

    it "rejects non-string variable description" do
      result = validate(valid_swarm(variables: { "MY_VAR" => { description: 42 } }))
      expect(result).to be_invalid
      expect(result.errors).to include("variables.MY_VAR.description must be a string")
    end

    it "rejects non-boolean required field" do
      result = validate(valid_swarm(variables: { "MY_VAR" => { required: "yes" } }))
      expect(result).to be_invalid
      expect(result.errors).to include("variables.MY_VAR.required must be a boolean")
    end

    it "rejects invalid variable type" do
      result = validate(valid_swarm(variables: { "MY_VAR" => { type: "float" } }))
      expect(result).to be_invalid
      expect(result.errors).to include(match(/variables.MY_VAR.type must be one of/))
    end

    it "accepts valid variable types" do
      %w[string integer boolean].each do |type|
        result = validate(valid_swarm(variables: { "MY_VAR" => { type: type } }))
        expect(result).to be_valid, "Expected #{type} to be valid but got: #{result.errors}"
      end
    end

    it "accepts variable with all fields" do
      result = validate(valid_swarm(variables: {
        "API_KEY" => { description: "API key", required: true, type: "string", default: "abc" }
      }))
      expect(result).to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Agents
  # ---------------------------------------------------------------------------
  describe "agents validation" do
    it "is optional (no agents is valid)" do
      data = { swarm_version: "1.0", name: "No Agents Swarm" }
      expect(validate(data)).to be_valid
    end

    it "rejects non-array agents" do
      result = validate(valid_swarm(agents: { name: "solo" }))
      expect(result).to be_invalid
      expect(result.errors).to include("agents must be an array")
    end

    it "rejects non-hash agent entries" do
      result = validate(valid_swarm(agents: ["bad"]))
      expect(result).to be_invalid
      expect(result.errors).to include("agents[0] must be an object")
    end

    it "requires agent name" do
      result = validate(valid_swarm(agents: [{ role: "Engineer" }]))
      expect(result).to be_invalid
      expect(result.errors).to include("agents[0].name is required")
    end

    it "requires agent role" do
      result = validate(valid_swarm(agents: [{ name: "Mando" }]))
      expect(result).to be_invalid
      expect(result.errors).to include("agents[0].role is required")
    end

    it "accepts minimal valid agent" do
      result = validate(valid_swarm(agents: [{ name: "Mando", role: "Engineer" }]))
      expect(result).to be_valid
    end

    it "rejects non-string agent soul" do
      result = validate(valid_swarm(agents: [{ name: "Mando", role: "Engineer", soul: 123 }]))
      expect(result).to be_invalid
      expect(result.errors).to include("agents[0].soul must be a string")
    end

    it "rejects non-string agent model" do
      result = validate(valid_swarm(agents: [{ name: "Mando", role: "Engineer", model: [] }]))
      expect(result).to be_invalid
      expect(result.errors).to include("agents[0].model must be a string")
    end

    describe "thinking config" do
      it "rejects non-integer thinking_budget_tokens" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", thinking_budget_tokens: "big" }]))
        expect(result).to be_invalid
        expect(result.errors).to include("agents[0].thinking_budget_tokens must be an integer")
      end

      it "rejects thinking_budget_tokens below 1" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", thinking_budget_tokens: 0 }]))
        expect(result).to be_invalid
        expect(result.errors).to include(match(/thinking_budget_tokens must be between/))
      end

      it "rejects thinking_budget_tokens above 128000" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", thinking_budget_tokens: 200_000 }]))
        expect(result).to be_invalid
        expect(result.errors).to include(match(/thinking_budget_tokens must be between/))
      end

      it "accepts thinking_budget_tokens within range" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", thinking_budget_tokens: 10_000 }]))
        expect(result).to be_valid
      end

      it "rejects invalid thinking_visibility" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", thinking_visibility: "visible" }]))
        expect(result).to be_invalid
        expect(result.errors).to include(match(/thinking_visibility must be one of/))
      end

      it "accepts valid thinking_visibility values" do
        %w[hidden debug].each do |v|
          result = validate(valid_swarm(agents: [{ name: "A", role: "B", thinking_visibility: v }]))
          expect(result).to be_valid, "Expected #{v} to be valid"
        end
      end
    end

    describe "agent skill/tool/mcp_server refs" do
      it "rejects non-array skills ref" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", skills: "all" }]))
        expect(result).to be_invalid
        expect(result.errors).to include("agents[0].skills must be an array")
      end

      it "rejects non-string skill ref item" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", skills: [123] }]))
        expect(result).to be_invalid
        expect(result.errors).to include(match(/agents\[0\]\.skills\[0\] must be a string reference/))
      end

      it "rejects non-array tools ref" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", tools: "all" }]))
        expect(result).to be_invalid
        expect(result.errors).to include("agents[0].tools must be an array")
      end

      it "rejects non-array mcp_servers ref" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", mcp_servers: "all" }]))
        expect(result).to be_invalid
        expect(result.errors).to include("agents[0].mcp_servers must be an array")
      end
    end

    describe "agent channels" do
      it "rejects non-array channels" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", channels: "slack" }]))
        expect(result).to be_invalid
        expect(result.errors).to include("agents[0].channels must be an array")
      end

      it "rejects non-hash channel entry" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", channels: ["slack"] }]))
        expect(result).to be_invalid
        expect(result.errors).to include("agents[0].channels[0] must be an object")
      end

      it "requires channel_ref in channel entry" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", channels: [{ foo: "bar" }] }]))
        expect(result).to be_invalid
        expect(result.errors).to include("agents[0].channels[0].channel_ref is required")
      end

      it "accepts valid channel entry" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", channels: [{ channel_ref: "main-slack" }] }]))
        expect(result).to be_valid
      end
    end

    describe "agent scheduled_tasks" do
      it "rejects non-array scheduled_tasks" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", scheduled_tasks: "daily" }]))
        expect(result).to be_invalid
        expect(result.errors).to include("agents[0].scheduled_tasks must be an array")
      end

      it "rejects non-hash scheduled_task entry" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", scheduled_tasks: ["bad"] }]))
        expect(result).to be_invalid
        expect(result.errors).to include("agents[0].scheduled_tasks[0] must be an object")
      end

      it "requires scheduled_task name" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", scheduled_tasks: [{ schedule: "0 9 * * *" }] }]))
        expect(result).to be_invalid
        expect(result.errors).to include("agents[0].scheduled_tasks[0].name is required")
      end

      it "requires scheduled_task schedule" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", scheduled_tasks: [{ name: "Daily" }] }]))
        expect(result).to be_invalid
        expect(result.errors).to include("agents[0].scheduled_tasks[0].schedule is required")
      end

      it "rejects invalid cron expression" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", scheduled_tasks: [{ name: "Daily", schedule: "not-a-cron" }] }]))
        expect(result).to be_invalid
        expect(result.errors).to include(match(/invalid cron expression/))
      end

      it "accepts valid cron expression" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", scheduled_tasks: [{ name: "Daily", schedule: "0 9 * * *" }] }]))
        expect(result).to be_valid
      end
    end

    describe "agent egress_policy" do
      it "rejects non-hash egress_policy" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", egress_policy: "open" }]))
        expect(result).to be_invalid
        expect(result.errors).to include("agents[0].egress_policy must be an object")
      end

      it "rejects invalid egress mode" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", egress_policy: { mode: "open" } }]))
        expect(result).to be_invalid
        expect(result.errors).to include(match(/egress_policy.mode must be one of/))
      end

      it "accepts valid egress modes" do
        %w[allowlist blocklist disabled].each do |mode|
          result = validate(valid_swarm(agents: [{ name: "A", role: "B", egress_policy: { mode: mode } }]))
          expect(result).to be_valid, "Expected #{mode} to be valid"
        end
      end

      it "rejects non-array domains" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", egress_policy: { mode: "allowlist", domains: "example.com" } }]))
        expect(result).to be_invalid
        expect(result.errors).to include("agents[0].egress_policy.domains must be an array")
      end
    end

    describe "agent workspace_files" do
      it "rejects non-array workspace_files" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", workspace_files: "README.md" }]))
        expect(result).to be_invalid
        expect(result.errors).to include("agents[0].workspace_files must be an array")
      end

      it "rejects directory traversal paths" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", workspace_files: ["../secrets.env"] }]))
        expect(result).to be_invalid
        expect(result.errors).to include(match(/must be a relative path without directory traversal/))
      end

      it "rejects absolute paths" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", workspace_files: ["/etc/passwd"] }]))
        expect(result).to be_invalid
        expect(result.errors).to include(match(/must be a relative path without directory traversal/))
      end

      it "accepts relative paths" do
        result = validate(valid_swarm(agents: [{ name: "A", role: "B", workspace_files: ["docs/README.md"] }]))
        expect(result).to be_valid
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Skills
  # ---------------------------------------------------------------------------
  describe "skills validation" do
    it "is optional" do
      result = validate(valid_swarm)
      expect(result).to be_valid
    end

    it "rejects non-array skills" do
      result = validate(valid_swarm(skills: { name: "my-skill" }))
      expect(result).to be_invalid
      expect(result.errors).to include("skills must be an array")
    end

    it "rejects non-hash skill entries" do
      result = validate(valid_swarm(skills: ["bad"]))
      expect(result).to be_invalid
      expect(result.errors).to include("skills[0] must be an object")
    end

    it "requires skill name" do
      result = validate(valid_swarm(skills: [{ summary: "A skill" }]))
      expect(result).to be_invalid
      expect(result.errors).to include("skills[0].name is required")
    end

    it "rejects non-string skill summary" do
      result = validate(valid_swarm(skills: [{ name: "my-skill", summary: 42 }]))
      expect(result).to be_invalid
      expect(result.errors).to include("skills[0].summary must be a string")
    end

    it "rejects summary exceeding 150 characters" do
      result = validate(valid_swarm(skills: [{ name: "my-skill", summary: "x" * 151 }]))
      expect(result).to be_invalid
      expect(result.errors).to include("skills[0].summary exceeds 150 character limit")
    end

    it "rejects content exceeding 100KB" do
      result = validate(valid_swarm(skills: [{ name: "my-skill", content: "x" * (100 * 1024 + 1) }]))
      expect(result).to be_invalid
      expect(result.errors).to include("skills[0].content exceeds 100KB limit")
    end

    it "rejects invalid skill category" do
      result = validate(valid_swarm(skills: [{ name: "my-skill", category: "hacking" }]))
      expect(result).to be_invalid
      expect(result.errors).to include(match(/skills\[0\]\.category must be one of/))
    end

    it "accepts valid skill categories" do
      %w[coding productivity automation messaging lifestyle utilities integrations].each do |cat|
        result = validate(valid_swarm(skills: [{ name: "my-skill", category: cat }]))
        expect(result).to be_valid, "Expected #{cat} to be a valid category"
      end
    end

    it "rejects non-array skill tools" do
      result = validate(valid_swarm(skills: [{ name: "my-skill", tools: "all" }]))
      expect(result).to be_invalid
      expect(result.errors).to include("skills[0].tools must be an array")
    end

    it "rejects non-string skill tool items" do
      result = validate(valid_swarm(skills: [{ name: "my-skill", tools: [42] }]))
      expect(result).to be_invalid
      expect(result.errors).to include("skills[0].tools[0] must be a string")
    end
  end

  # ---------------------------------------------------------------------------
  # Tools
  # ---------------------------------------------------------------------------
  describe "tools validation" do
    it "is optional" do
      result = validate(valid_swarm)
      expect(result).to be_valid
    end

    it "rejects non-array tools" do
      result = validate(valid_swarm(tools: "all"))
      expect(result).to be_invalid
      expect(result.errors).to include("tools must be an array")
    end

    it "rejects non-hash tool entries" do
      result = validate(valid_swarm(tools: ["bad"]))
      expect(result).to be_invalid
      expect(result.errors).to include("tools[0] must be an object")
    end

    it "requires tool name" do
      result = validate(valid_swarm(tools: [{ description: "A tool" }]))
      expect(result).to be_invalid
      expect(result.errors).to include("tools[0].name is required")
    end

    it "accepts valid tool" do
      result = validate(valid_swarm(tools: [{ name: "my-tool", description: "Does something" }]))
      expect(result).to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Channels
  # ---------------------------------------------------------------------------
  describe "channels validation" do
    it "is optional" do
      result = validate(valid_swarm)
      expect(result).to be_valid
    end

    it "rejects non-array channels" do
      result = validate(valid_swarm(channels: { name: "slack" }))
      expect(result).to be_invalid
      expect(result.errors).to include("channels must be an array")
    end

    it "rejects non-hash channel entries" do
      result = validate(valid_swarm(channels: ["bad"]))
      expect(result).to be_invalid
      expect(result.errors).to include("channels[0] must be an object")
    end

    it "requires channel ref" do
      result = validate(valid_swarm(channels: [{ name: "Main Slack", type: "slack" }]))
      expect(result).to be_invalid
      expect(result.errors).to include("channels[0].ref is required")
    end

    it "requires channel name" do
      result = validate(valid_swarm(channels: [{ ref: "main-slack", type: "slack" }]))
      expect(result).to be_invalid
      expect(result.errors).to include("channels[0].name is required")
    end

    it "requires channel type" do
      result = validate(valid_swarm(channels: [{ ref: "main-slack", name: "Main Slack" }]))
      expect(result).to be_invalid
      expect(result.errors).to include("channels[0].type is required")
    end

    it "rejects invalid channel type" do
      result = validate(valid_swarm(channels: [{ ref: "main-slack", name: "Main", type: "irc" }]))
      expect(result).to be_invalid
      expect(result.errors).to include(match(/channels\[0\]\.type must be one of/))
    end

    it "accepts all valid channel types" do
      %w[slack discord telegram whatsapp signal web].each do |type|
        result = validate(valid_swarm(channels: [{ ref: "ch", name: "Chan", type: type }]))
        expect(result).to be_valid, "Expected #{type} to be valid"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # MCP Servers
  # ---------------------------------------------------------------------------
  describe "mcp_servers validation" do
    it "is optional" do
      result = validate(valid_swarm)
      expect(result).to be_valid
    end

    it "rejects non-array mcp_servers" do
      result = validate(valid_swarm(mcp_servers: "all"))
      expect(result).to be_invalid
      expect(result.errors).to include("mcp_servers must be an array")
    end

    it "rejects non-hash mcp_server entries" do
      result = validate(valid_swarm(mcp_servers: ["bad"]))
      expect(result).to be_invalid
      expect(result.errors).to include("mcp_servers[0] must be an object")
    end

    it "requires mcp_server name" do
      result = validate(valid_swarm(mcp_servers: [{ transport: "stdio", command: "node server.js" }]))
      expect(result).to be_invalid
      expect(result.errors).to include("mcp_servers[0].name is required")
    end

    it "requires mcp_server transport" do
      result = validate(valid_swarm(mcp_servers: [{ name: "my-mcp" }]))
      expect(result).to be_invalid
      expect(result.errors).to include("mcp_servers[0].transport is required")
    end

    it "rejects invalid transport" do
      result = validate(valid_swarm(mcp_servers: [{ name: "my-mcp", transport: "http" }]))
      expect(result).to be_invalid
      expect(result.errors).to include(match(/transport must be one of/))
    end

    it "accepts stdio transport" do
      result = validate(valid_swarm(mcp_servers: [{ name: "my-mcp", transport: "stdio", command: "node s.js" }]))
      expect(result).to be_valid
    end

    it "accepts sse transport" do
      result = validate(valid_swarm(mcp_servers: [{ name: "my-mcp", transport: "sse", url: "https://mcp.example.com" }]))
      expect(result).to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # API Integrations
  # ---------------------------------------------------------------------------
  describe "api_integrations validation" do
    it "is optional" do
      result = validate(valid_swarm)
      expect(result).to be_valid
    end

    it "rejects non-array api_integrations" do
      result = validate(valid_swarm(api_integrations: { name: "stripe" }))
      expect(result).to be_invalid
      expect(result.errors).to include("api_integrations must be an array")
    end

    it "rejects non-hash api_integration entries" do
      result = validate(valid_swarm(api_integrations: ["bad"]))
      expect(result).to be_invalid
      expect(result.errors).to include("api_integrations[0] must be an object")
    end

    it "requires api_integration name" do
      result = validate(valid_swarm(api_integrations: [{ base_url: "https://api.stripe.com" }]))
      expect(result).to be_invalid
      expect(result.errors).to include("api_integrations[0].name is required")
    end

    it "requires api_integration base_url" do
      result = validate(valid_swarm(api_integrations: [{ name: "stripe" }]))
      expect(result).to be_invalid
      expect(result.errors).to include("api_integrations[0].base_url is required")
    end

    it "rejects non-array endpoints" do
      result = validate(valid_swarm(api_integrations: [{ name: "stripe", base_url: "https://api.stripe.com", endpoints: "all" }]))
      expect(result).to be_invalid
      expect(result.errors).to include("api_integrations[0].endpoints must be an array")
    end

    it "rejects non-hash endpoint entries" do
      result = validate(valid_swarm(api_integrations: [{ name: "stripe", base_url: "https://api.stripe.com", endpoints: ["bad"] }]))
      expect(result).to be_invalid
      expect(result.errors).to include("api_integrations[0].endpoints[0] must be an object")
    end

    it "requires endpoint method" do
      result = validate(valid_swarm(api_integrations: [{ name: "stripe", base_url: "https://api.stripe.com", endpoints: [{ path: "/charges" }] }]))
      expect(result).to be_invalid
      expect(result.errors).to include("api_integrations[0].endpoints[0].method is required")
    end

    it "requires endpoint path" do
      result = validate(valid_swarm(api_integrations: [{ name: "stripe", base_url: "https://api.stripe.com", endpoints: [{ method: "GET" }] }]))
      expect(result).to be_invalid
      expect(result.errors).to include("api_integrations[0].endpoints[0].path is required")
    end

    it "accepts valid api_integration with endpoints" do
      result = validate(valid_swarm(api_integrations: [{
        name: "stripe",
        base_url: "https://api.stripe.com",
        endpoints: [{ method: "GET", path: "/charges" }]
      }]))
      expect(result).to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Error accumulation (no fail-fast)
  # ---------------------------------------------------------------------------
  describe "error accumulation" do
    it "collects multiple errors across sections" do
      data = {
        swarm_version: "1.0",
        name: 42,
        tags: "not-an-array",
        agents: [{ soul: "no name or role" }],
        channels: [{ name: "Chan", type: "irc" }]
      }
      result = validate(data)
      expect(result).to be_invalid
      expect(result.errors.size).to be > 3
    end
  end

  # ---------------------------------------------------------------------------
  # Full DevOps swarm example
  # ---------------------------------------------------------------------------
  describe "realistic DevOps swarm" do
    let(:devops_swarm) do
      {
        swarm_version: "1.0",
        name: "DevOps Dream Team",
        slug: "devops-dream-team",
        description: "Full CI/CD automation team",
        author: { name: "Platform Team", url: "https://platform.example.com" },
        version: "2.1.0",
        license: "MIT",
        tags: %w[devops ci-cd automation],
        requires: {
          hivemind_version: ">=3.0",
          integrations: ["github", "pagerduty"],
          provider_models: ["claude-3-5-sonnet"]
        },
        team: {
          name: "DevOps Dream Team",
          description: "Automates the full software delivery pipeline"
        },
        agents: [
          {
            name: "Watcher",
            role: "DevOps Engineer",
            model: "claude-3-5-sonnet",
            skills: ["devops-core"],
            tools: ["github-tool"],
            channels: [{ channel_ref: "main-slack" }],
            scheduled_tasks: [{ name: "Daily Deploy", schedule: "0 9 * * 1-5" }],
            egress_policy: { mode: "allowlist", domains: ["github.com", "api.pagerduty.com"] },
            workspace_files: ["scripts/deploy.sh"]
          }
        ],
        skills: [
          {
            name: "devops-core",
            summary: "Core DevOps knowledge",
            category: "automation",
            tools: ["github-tool"]
          }
        ],
        tools: [{ name: "github-tool", description: "GitHub automation" }],
        channels: [{ ref: "main-slack", name: "Main Slack", type: "slack" }],
        mcp_servers: [{ name: "github-mcp", transport: "stdio", command: "npx github-mcp" }],
        api_integrations: [{
          name: "pagerduty",
          base_url: "https://api.pagerduty.com",
          endpoints: [{ method: "POST", path: "/incidents" }]
        }],
        variables: {
          "GITHUB_TOKEN" => { description: "GitHub PAT", required: true, type: "string" }
        }
      }
    end

    it "validates a realistic DevOps swarm as valid" do
      expect(validate(devops_swarm)).to be_valid
    end
  end
end
