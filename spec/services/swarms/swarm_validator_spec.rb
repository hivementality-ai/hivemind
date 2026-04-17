# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::SwarmValidator do
  subject(:validator) { described_class.new }

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def validate(data)
    validator.validate(data)
  end

  # A valid, fully cross-referenced swarm. Each test mutates this baseline
  # to exercise one failure condition at a time.
  def valid_swarm(**overrides)
    base = {
      swarm_version: "1.0",
      name: "Test Swarm",
      agents: [
        {
          name: "Mando",
          role: "Engineer",
          skills:      ["core-skill"],
          tools:       ["my-tool"],
          mcp_servers: ["my-mcp"],
          channels:    [{ channel_ref: "main-slack" }]
        }
      ],
      skills: [
        { name: "core-skill", summary: "Core engineering knowledge" }
      ],
      tools: [
        { name: "my-tool", description: "Does something" }
      ],
      channels: [
        { ref: "main-slack", name: "Main Slack", type: "slack" }
      ],
      mcp_servers: [
        { name: "my-mcp", transport: "stdio", command: "npx my-mcp" }
      ],
      api_integrations: [
        { name: "stripe", base_url: "https://api.stripe.com" }
      ]
    }
    base.deep_merge(overrides)
  end

  # ---------------------------------------------------------------------------
  # ValidationResult
  # ---------------------------------------------------------------------------

  describe "ValidationResult" do
    it "is valid when errors are empty" do
      result = Swarms::SwarmValidator::ValidationResult.new(errors: [])
      expect(result).to be_valid
      expect(result).not_to be_invalid
    end

    it "is invalid when errors are present" do
      err = Swarms::SwarmValidator::ValidationError.new(path: "agents[0].skills[0]", message: "oops")
      result = Swarms::SwarmValidator::ValidationResult.new(errors: [err])
      expect(result).to be_invalid
      expect(result).not_to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # ValidationError
  # ---------------------------------------------------------------------------

  describe "ValidationError" do
    let(:error) { Swarms::SwarmValidator::ValidationError.new(path: "skills[0].content", message: "too big") }

    it "exposes path and message" do
      expect(error.path).to eq("skills[0].content")
      expect(error.message).to eq("too big")
    end

    it "formats full_message as 'path: message'" do
      expect(error.full_message).to eq("skills[0].content: too big")
    end

    it "to_s delegates to full_message" do
      expect(error.to_s).to eq("skills[0].content: too big")
    end
  end

  # ---------------------------------------------------------------------------
  # Root type guard
  # ---------------------------------------------------------------------------

  describe "root type guard" do
    it "returns invalid result when given a non-Hash" do
      result = validate([1, 2, 3])
      expect(result).to be_invalid
    end

    it "returns invalid result for nil" do
      result = validate(nil)
      expect(result).to be_invalid
    end

    it "returns invalid result for a string" do
      result = validate("nope")
      expect(result).to be_invalid
    end
  end

  # ---------------------------------------------------------------------------
  # Happy path — fully valid swarm
  # ---------------------------------------------------------------------------

  describe "fully valid swarm" do
    it "returns valid when all refs resolve and names are unique" do
      expect(validate(valid_swarm)).to be_valid
    end

    it "accepts a swarm with no agents" do
      data = { swarm_version: "1.0", name: "Bare Swarm" }
      expect(validate(data)).to be_valid
    end

    it "accepts a swarm with agents that have no cross-refs" do
      data = valid_swarm(agents: [{ name: "Solo", role: "Engineer" }])
      expect(validate(data)).to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Uniqueness — agents
  # ---------------------------------------------------------------------------

  describe "uniqueness: agents" do
    it "rejects duplicate agent names" do
      result = validate(valid_swarm(
        agents: [
          { name: "Mando", role: "Engineer" },
          { name: "Mando", role: "Designer" }
        ]
      ))
      expect(result).to be_invalid
      expect(result.errors.map(&:path)).to include("agents[1].name")
      expect(result.errors.map(&:message).join).to include("duplicate")
    end

    it "accepts agents with distinct names" do
      result = validate(valid_swarm(
        agents: [
          { name: "Mando", role: "Engineer" },
          { name: "Grogu", role: "Designer" }
        ]
      ))
      expect(result).to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Uniqueness — skills
  # ---------------------------------------------------------------------------

  describe "uniqueness: skills" do
    it "rejects duplicate skill names" do
      result = validate(valid_swarm(
        skills: [
          { name: "core-skill" },
          { name: "core-skill" }
        ]
      ))
      expect(result).to be_invalid
      expect(result.errors.map(&:path)).to include("skills[1].name")
      expect(result.errors.map(&:message).join).to include("duplicate")
    end

    it "accepts skills with distinct names" do
      result = validate(valid_swarm(
        agents: [{ name: "Mando", role: "Engineer" }],
        skills: [{ name: "skill-a" }, { name: "skill-b" }]
      ))
      expect(result).to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Uniqueness — tools
  # ---------------------------------------------------------------------------

  describe "uniqueness: tools" do
    it "rejects duplicate tool names" do
      result = validate(valid_swarm(
        tools: [
          { name: "my-tool" },
          { name: "my-tool" }
        ]
      ))
      expect(result).to be_invalid
      expect(result.errors.map(&:path)).to include("tools[1].name")
    end
  end

  # ---------------------------------------------------------------------------
  # Uniqueness — channels
  # ---------------------------------------------------------------------------

  describe "uniqueness: channels" do
    it "rejects duplicate channel refs" do
      result = validate(valid_swarm(
        channels: [
          { ref: "main-slack", name: "Main Slack", type: "slack" },
          { ref: "main-slack", name: "Duplicate",  type: "slack" }
        ]
      ))
      expect(result).to be_invalid
      expect(result.errors.map(&:path)).to include("channels[1].ref")
    end

    it "accepts channels with distinct refs" do
      result = validate(valid_swarm(
        channels: [
          { ref: "slack-1", name: "Slack 1", type: "slack" },
          { ref: "slack-2", name: "Slack 2", type: "slack" }
        ]
      ))
      expect(result).to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Uniqueness — mcp_servers
  # ---------------------------------------------------------------------------

  describe "uniqueness: mcp_servers" do
    it "rejects duplicate mcp_server names" do
      result = validate(valid_swarm(
        mcp_servers: [
          { name: "my-mcp", transport: "stdio", command: "npx a" },
          { name: "my-mcp", transport: "stdio", command: "npx b" }
        ]
      ))
      expect(result).to be_invalid
      expect(result.errors.map(&:path)).to include("mcp_servers[1].name")
    end
  end

  # ---------------------------------------------------------------------------
  # Uniqueness — api_integrations
  # ---------------------------------------------------------------------------

  describe "uniqueness: api_integrations" do
    it "rejects duplicate api_integration names" do
      result = validate(valid_swarm(
        api_integrations: [
          { name: "stripe", base_url: "https://a.com" },
          { name: "stripe", base_url: "https://b.com" }
        ]
      ))
      expect(result).to be_invalid
      expect(result.errors.map(&:path)).to include("api_integrations[1].name")
    end

    it "accepts api_integrations with distinct names" do
      result = validate(valid_swarm(
        api_integrations: [
          { name: "stripe", base_url: "https://stripe.com" },
          { name: "github", base_url: "https://api.github.com" }
        ]
      ))
      expect(result).to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Referential integrity — agent.skills[]
  # ---------------------------------------------------------------------------

  describe "referential integrity: agent skills" do
    it "rejects a skill ref that has no matching skill name" do
      result = validate(valid_swarm(
        agents: [{ name: "Mando", role: "Engineer", skills: ["nonexistent-skill"] }],
        skills: [{ name: "core-skill" }]
      ))
      expect(result).to be_invalid
      expect(result.errors.map(&:path)).to include("agents[0].skills[0]")
      expect(result.errors.map(&:message).join).to include("nonexistent-skill")
    end

    it "accepts a skill ref that matches an existing skill name" do
      result = validate(valid_swarm(
        agents: [{ name: "Mando", role: "Engineer", skills: ["core-skill"] }],
        skills: [{ name: "core-skill" }]
      ))
      expect(result).to be_valid
    end

    it "reports errors for each invalid ref in a multi-item list" do
      result = validate(valid_swarm(
        agents: [{ name: "Mando", role: "Engineer", skills: ["missing-a", "core-skill", "missing-b"] }],
        skills: [{ name: "core-skill" }]
      ))
      expect(result).to be_invalid
      paths = result.errors.map(&:path)
      expect(paths).to include("agents[0].skills[0]")
      expect(paths).to include("agents[0].skills[2]")
      expect(paths).not_to include("agents[0].skills[1]")
    end

    it "skips integrity check when agent has no skills array" do
      result = validate(valid_swarm(
        agents: [{ name: "Mando", role: "Engineer" }],
        skills: []
      ))
      expect(result).to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Referential integrity — agent.tools[]
  # ---------------------------------------------------------------------------

  describe "referential integrity: agent tools" do
    it "rejects a tool ref with no matching tool name" do
      result = validate(valid_swarm(
        agents: [{ name: "Mando", role: "Engineer", tools: ["ghost-tool"] }],
        tools:  [{ name: "my-tool" }]
      ))
      expect(result).to be_invalid
      expect(result.errors.map(&:path)).to include("agents[0].tools[0]")
      expect(result.errors.map(&:message).join).to include("ghost-tool")
    end

    it "accepts a tool ref that resolves correctly" do
      result = validate(valid_swarm(
        agents: [{ name: "Mando", role: "Engineer", tools: ["my-tool"] }],
        tools:  [{ name: "my-tool" }]
      ))
      expect(result).to be_valid
    end

    it "rejects tool refs when tools section is absent" do
      swarm = {
        swarm_version: "1.0",
        name: "No Tools Swarm",
        agents: [{ name: "Mando", role: "Engineer", tools: ["some-tool"] }]
      }
      result = validate(swarm)
      expect(result).to be_invalid
      expect(result.errors.map(&:path)).to include("agents[0].tools[0]")
    end
  end

  # ---------------------------------------------------------------------------
  # Referential integrity — agent.mcp_servers[]
  # ---------------------------------------------------------------------------

  describe "referential integrity: agent mcp_servers" do
    it "rejects an mcp_server ref with no matching mcp_server name" do
      result = validate(valid_swarm(
        agents:      [{ name: "Mando", role: "Engineer", mcp_servers: ["ghost-mcp"] }],
        mcp_servers: [{ name: "my-mcp", transport: "stdio", command: "npx a" }]
      ))
      expect(result).to be_invalid
      expect(result.errors.map(&:path)).to include("agents[0].mcp_servers[0]")
      expect(result.errors.map(&:message).join).to include("ghost-mcp")
    end

    it "accepts a valid mcp_server ref" do
      result = validate(valid_swarm(
        agents:      [{ name: "Mando", role: "Engineer", mcp_servers: ["my-mcp"] }],
        mcp_servers: [{ name: "my-mcp", transport: "stdio", command: "npx a" }]
      ))
      expect(result).to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Referential integrity — agent.channels[].channel_ref
  # ---------------------------------------------------------------------------

  describe "referential integrity: agent channels" do
    it "rejects a channel_ref with no matching channel ref" do
      result = validate(valid_swarm(
        agents:   [{ name: "Mando", role: "Engineer", channels: [{ channel_ref: "ghost-channel" }] }],
        channels: [{ ref: "main-slack", name: "Main Slack", type: "slack" }]
      ))
      expect(result).to be_invalid
      expect(result.errors.map(&:path)).to include("agents[0].channels[0].channel_ref")
      expect(result.errors.map(&:message).join).to include("ghost-channel")
    end

    it "accepts a channel_ref that resolves correctly" do
      result = validate(valid_swarm(
        agents:   [{ name: "Mando", role: "Engineer", channels: [{ channel_ref: "main-slack" }] }],
        channels: [{ ref: "main-slack", name: "Main Slack", type: "slack" }]
      ))
      expect(result).to be_valid
    end

    it "rejects channel_ref when channels section is absent" do
      swarm = {
        swarm_version: "1.0",
        name: "No Channels Swarm",
        agents: [{ name: "Mando", role: "Engineer", channels: [{ channel_ref: "slack" }] }]
      }
      result = validate(swarm)
      expect(result).to be_invalid
      expect(result.errors.map(&:path)).to include("agents[0].channels[0].channel_ref")
    end

    it "ignores blank channel_refs (structural schema catches those)" do
      result = validate(valid_swarm(
        agents:   [{ name: "Mando", role: "Engineer", channels: [{ channel_ref: "" }] }],
        channels: [{ ref: "main-slack", name: "Main Slack", type: "slack" }]
      ))
      expect(result).to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Size limits — skill.summary
  # ---------------------------------------------------------------------------

  describe "size limits: skill.summary" do
    it "accepts summary exactly at 150 chars" do
      result = validate(valid_swarm(
        skills: [{ name: "core-skill", summary: "a" * 150 }]
      ))
      expect(result).to be_valid
    end

    it "rejects summary exceeding 150 chars" do
      result = validate(valid_swarm(
        skills: [{ name: "core-skill", summary: "a" * 151 }]
      ))
      expect(result).to be_invalid
      expect(result.errors.map(&:path)).to include("skills[0].summary")
      expect(result.errors.map(&:message).join).to include("150")
    end

    it "includes the actual character count in the message" do
      result = validate(valid_swarm(
        skills: [{ name: "core-skill", summary: "a" * 200 }]
      ))
      err = result.errors.find { |e| e.path == "skills[0].summary" }
      expect(err.message).to include("200")
    end
  end

  # ---------------------------------------------------------------------------
  # Size limits — skill.content
  # ---------------------------------------------------------------------------

  describe "size limits: skill.content" do
    let(:limit) { 100 * 1024 }

    it "accepts content exactly at 100KB" do
      result = validate(valid_swarm(
        skills: [{ name: "core-skill", content: "a" * limit }]
      ))
      expect(result).to be_valid
    end

    it "rejects content exceeding 100KB" do
      result = validate(valid_swarm(
        skills: [{ name: "core-skill", content: "a" * (limit + 1) }]
      ))
      expect(result).to be_invalid
      expect(result.errors.map(&:path)).to include("skills[0].content")
      expect(result.errors.map(&:message).join).to include("100KB")
    end

    it "includes the actual byte size in the message" do
      result = validate(valid_swarm(
        skills: [{ name: "core-skill", content: "a" * (limit + 500) }]
      ))
      err = result.errors.find { |e| e.path == "skills[0].content" }
      expect(err.message).to include((limit + 500).to_s)
    end
  end

  # ---------------------------------------------------------------------------
  # Size limits — tool.script_template
  # ---------------------------------------------------------------------------

  describe "size limits: tool.script_template" do
    let(:limit) { 100 * 1024 }

    it "accepts script_template exactly at 100KB" do
      result = validate(valid_swarm(
        tools: [{ name: "my-tool", script_template: "a" * limit }]
      ))
      expect(result).to be_valid
    end

    it "rejects script_template exceeding 100KB" do
      result = validate(valid_swarm(
        tools: [{ name: "my-tool", script_template: "a" * (limit + 1) }]
      ))
      expect(result).to be_invalid
      expect(result.errors.map(&:path)).to include("tools[0].script_template")
      expect(result.errors.map(&:message).join).to include("100KB")
    end
  end

  # ---------------------------------------------------------------------------
  # Error accumulation — multiple failures at once
  # ---------------------------------------------------------------------------

  describe "error accumulation" do
    it "reports all errors without fail-fast" do
      result = validate(valid_swarm(
        agents: [
          { name: "Mando", role: "Engineer", skills: ["missing-skill"], tools: ["missing-tool"] },
          { name: "Mando", role: "Designer" }  # duplicate name
        ],
        skills: [{ name: "other-skill" }],
        tools:  [{ name: "other-tool" }]
      ))

      expect(result).to be_invalid
      paths = result.errors.map(&:path)
      # duplicate agent name
      expect(paths).to include("agents[1].name")
      # bad skill ref
      expect(paths).to include("agents[0].skills[0]")
      # bad tool ref
      expect(paths).to include("agents[0].tools[0]")
    end

    it "collects uniqueness + referential + size errors together" do
      result = validate(valid_swarm(
        skills: [
          { name: "core-skill", summary: "a" * 200 },
          { name: "core-skill", summary: "dup" }  # duplicate name AND summary over limit
        ]
      ))
      expect(result).to be_invalid
      paths = result.errors.map(&:path)
      expect(paths).to include("skills[1].name")
      expect(paths).to include("skills[0].summary")
    end
  end

  # ---------------------------------------------------------------------------
  # Multi-agent cross-referencing
  # ---------------------------------------------------------------------------

  describe "multi-agent cross-referencing" do
    it "validates refs independently for each agent" do
      result = validate(valid_swarm(
        agents: [
          { name: "Mando",  role: "Engineer", skills: ["skill-a"] },
          { name: "Grogu",  role: "Designer", skills: ["skill-b"] },
          { name: "Bo",     role: "Planner",  skills: ["missing"] }
        ],
        skills: [
          { name: "skill-a" },
          { name: "skill-b" }
        ]
      ))
      expect(result).to be_invalid
      paths = result.errors.map(&:path)
      expect(paths).to include("agents[2].skills[0]")
      expect(paths).not_to include("agents[0].skills[0]")
      expect(paths).not_to include("agents[1].skills[0]")
    end
  end

  # ---------------------------------------------------------------------------
  # Realistic full swarm
  # ---------------------------------------------------------------------------

  describe "realistic full swarm" do
    it "validates a complete, fully cross-referenced swarm as valid" do
      swarm = {
        swarm_version: "1.0",
        name:          "DevOps Dream Team",
        slug:          "devops-dream",
        agents: [
          {
            name:        "Watcher",
            role:        "DevOps Engineer",
            skills:      ["devops-core", "monitoring"],
            tools:       ["github-tool", "pager-tool"],
            mcp_servers: ["github-mcp"],
            channels:    [{ channel_ref: "ops-slack" }, { channel_ref: "on-call-discord" }]
          },
          {
            name:        "Deployer",
            role:        "Release Engineer",
            skills:      ["devops-core"],
            tools:       ["github-tool"],
            mcp_servers: [],
            channels:    [{ channel_ref: "ops-slack" }]
          }
        ],
        skills: [
          { name: "devops-core",  summary: "Core DevOps practices",  category: "automation" },
          { name: "monitoring",   summary: "Observability and alerts", category: "automation" }
        ],
        tools: [
          { name: "github-tool", description: "GitHub automation" },
          { name: "pager-tool",  description: "PagerDuty integration" }
        ],
        channels: [
          { ref: "ops-slack",       name: "Ops Slack",       type: "slack" },
          { ref: "on-call-discord", name: "On-Call Discord", type: "discord" }
        ],
        mcp_servers: [
          { name: "github-mcp", transport: "stdio", command: "npx github-mcp" }
        ],
        api_integrations: [
          { name: "pagerduty", base_url: "https://api.pagerduty.com" },
          { name: "datadog",   base_url: "https://api.datadoghq.com" }
        ]
      }
      expect(validate(swarm)).to be_valid
    end
  end
end
