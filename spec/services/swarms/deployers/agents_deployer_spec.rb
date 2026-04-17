# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Deployers::AgentsDeployer do
  def build_document(agents: [])
    Swarms::SwarmDocument.new(
      swarm_version: "1.0",
      name:          "Test Swarm",
      agents:        agents
    )
  end

  # ---------------------------------------------------------------------------
  # Result contract
  # ---------------------------------------------------------------------------

  describe "result contract" do
    it "always returns a successful ServiceResponse" do
      result = described_class.call(document: build_document)
      expect(result).to be_success
    end

    it "returns an empty agents array when the document has no agents" do
      result = described_class.call(document: build_document(agents: []))
      expect(result.payload[:agents]).to eq([])
    end

    it "returns one DeployResult per agent in the document" do
      doc    = build_document(agents: [
        { "name" => "Agent A", "role" => "Engineer" },
        { "name" => "Agent B", "role" => "Reviewer" }
      ])
      result = described_class.call(document: doc)
      expect(result.payload[:agents].size).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # No conflict — create
  # ---------------------------------------------------------------------------

  describe "when no platform agent exists with that name" do
    it "creates a new Agent record" do
      doc = build_document(agents: [{ "name" => "Fresh Agent", "role" => "Coder" }])
      expect { described_class.call(document: doc) }.to change(Agent, :count).by(1)
    end

    it "returns action :created" do
      doc    = build_document(agents: [{ "name" => "Fresh Agent", "role" => "Coder" }])
      result = described_class.call(document: doc)
      expect(result.payload[:agents].first.action).to eq(:created)
    end

    it "stores name and role" do
      doc    = build_document(agents: [{ "name" => "Builder", "role" => "Software Engineer" }])
      result = described_class.call(document: doc)
      agent  = result.payload[:agents].first.record

      expect(agent.name).to eq("Builder")
      expect(agent.role).to eq("Software Engineer")
    end

    it "maps soul to system_prompt" do
      doc   = build_document(agents: [{ "name" => "Soulful", "role" => "R", "soul" => "I am a soul." }])
      agent = described_class.call(document: doc).payload[:agents].first.record
      expect(agent.system_prompt).to eq("I am a soul.")
    end

    it "falls back to system_prompt field when soul is absent" do
      doc   = build_document(agents: [{ "name" => "Prompted", "role" => "R", "system_prompt" => "Use me." }])
      agent = described_class.call(document: doc).payload[:agents].first.record
      expect(agent.system_prompt).to eq("Use me.")
    end

    it "stores llm model when provided" do
      doc   = build_document(agents: [{ "name" => "Modeled", "role" => "R", "model" => "claude-opus-4-5" }])
      agent = described_class.call(document: doc).payload[:agents].first.record
      expect(agent.llm_model).to eq("claude-opus-4-5")
    end

    it "stores thinking_enabled flag" do
      doc   = build_document(agents: [{ "name" => "Thinker", "role" => "R", "thinking_enabled" => true }])
      agent = described_class.call(document: doc).payload[:agents].first.record
      expect(agent.thinking_enabled).to be true
    end

    it "stores thinking_budget_tokens" do
      doc   = build_document(agents: [{ "name" => "Budgeter", "role" => "R", "thinking_budget_tokens" => 5000 }])
      agent = described_class.call(document: doc).payload[:agents].first.record
      expect(agent.thinking_budget_tokens).to eq(5000)
    end

    it "assigns the agent to the team when team is provided" do
      team = create(:team)
      doc  = build_document(agents: [{ "name" => "Team Member", "role" => "Tester" }])
      agent = described_class.call(document: doc, team: team).payload[:agents].first.record
      expect(agent.team).to eq(team)
    end

    it "does not assign team when team argument is nil" do
      doc   = build_document(agents: [{ "name" => "Solo Agent", "role" => "Ops" }])
      agent = described_class.call(document: doc, team: nil).payload[:agents].first.record
      expect(agent.team).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Skill + tool association wiring
  # ---------------------------------------------------------------------------

  describe "skill and tool association wiring" do
    it "associates listed skills with the created agent" do
      skill_a = create(:skill, name: "ruby-rails")
      skill_b = create(:skill, name: "tdd")
      doc     = build_document(agents: [{
        "name"   => "Ruby Dev",
        "role"   => "Engineer",
        "skills" => %w[ruby-rails tdd]
      }])

      agent = described_class.call(document: doc).payload[:agents].first.record
      expect(agent.skills).to match_array([skill_a, skill_b])
    end

    it "associates listed tools with the created agent" do
      tool = create(:tool, name: "bash-runner", executor_type: "custom_script", script_template: "x")
      doc  = build_document(agents: [{
        "name"  => "Tool User",
        "role"  => "Ops",
        "tools" => ["bash-runner"]
      }])

      agent = described_class.call(document: doc).payload[:agents].first.record
      expect(agent.tools).to match_array([tool])
    end

    it "silently skips skill names that do not exist in the database" do
      doc = build_document(agents: [{
        "name"   => "Orphan User",
        "role"   => "R",
        "skills" => ["nonexistent-skill"]
      }])

      agent = described_class.call(document: doc).payload[:agents].first.record
      expect(agent.skills).to be_empty
    end

    it "silently skips tool names that do not exist in the database" do
      doc = build_document(agents: [{
        "name"  => "Orphan User",
        "role"  => "R",
        "tools" => ["nonexistent-tool"]
      }])

      agent = described_class.call(document: doc).payload[:agents].first.record
      expect(agent.tools).to be_empty
    end

    it "creates no associations when skills and tools lists are absent" do
      doc   = build_document(agents: [{ "name" => "Plain Agent", "role" => "R" }])
      agent = described_class.call(document: doc).payload[:agents].first.record
      expect(agent.skills).to be_empty
      expect(agent.tools).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Strategy: :skip
  # ---------------------------------------------------------------------------

  describe "strategy :skip" do
    it "returns the existing agent without modification" do
      existing = create(:agent, name: "Veteran", role: "Old Role")
      doc      = build_document(agents: [{ "name" => "Veteran", "role" => "New Role" }])
      result   = described_class.call(document: doc, resolutions: { "Veteran" => :skip })

      dr = result.payload[:agents].first
      expect(dr.action).to eq(:skipped)
      expect(dr.record).to eq(existing)
      expect(existing.reload.role).to eq("Old Role")
    end

    it "does not create a new agent" do
      create(:agent, name: "Veteran", role: "R")
      doc = build_document(agents: [{ "name" => "Veteran", "role" => "R2" }])
      expect { described_class.call(document: doc, resolutions: { "Veteran" => :skip }) }.not_to change(Agent, :count)
    end
  end

  # ---------------------------------------------------------------------------
  # Strategy: :overwrite
  # ---------------------------------------------------------------------------

  describe "strategy :overwrite" do
    it "updates agent attributes" do
      existing = create(:agent, name: "Mutable", role: "Old Role", system_prompt: "Old prompt")
      doc      = build_document(agents: [{
        "name" => "Mutable",
        "role" => "New Role",
        "soul" => "New soul"
      }])
      result = described_class.call(document: doc, resolutions: { "Mutable" => :overwrite })

      dr = result.payload[:agents].first
      expect(dr.action).to eq(:updated)
      expect(existing.reload.role).to eq("New Role")
      expect(existing.reload.system_prompt).to eq("New soul")
    end

    it "replaces skill associations" do
      old_skill = create(:skill, name: "old-skill")
      new_skill = create(:skill, name: "new-skill")
      existing  = create(:agent, name: "Mutable", role: "R")
      existing.skills << old_skill

      doc = build_document(agents: [{
        "name"   => "Mutable",
        "role"   => "R",
        "skills" => ["new-skill"]
      }])
      described_class.call(document: doc, resolutions: { "Mutable" => :overwrite })

      expect(existing.reload.skills).to match_array([new_skill])
    end

    it "replaces tool associations" do
      old_tool = create(:tool, name: "old-tool", executor_type: "custom_script", script_template: "x")
      new_tool = create(:tool, name: "new-tool", executor_type: "custom_script", script_template: "y")
      existing = create(:agent, name: "Mutable", role: "R")
      existing.tools << old_tool

      doc = build_document(agents: [{
        "name"  => "Mutable",
        "role"  => "R",
        "tools" => ["new-tool"]
      }])
      described_class.call(document: doc, resolutions: { "Mutable" => :overwrite })

      expect(existing.reload.tools).to match_array([new_tool])
    end
  end

  # ---------------------------------------------------------------------------
  # Strategy: :rename
  # ---------------------------------------------------------------------------

  describe "strategy :rename" do
    it "creates a new agent with a suffixed name" do
      create(:agent, name: "Alpha Agent", role: "R")
      doc    = build_document(agents: [{ "name" => "Alpha Agent", "role" => "R" }])
      result = described_class.call(document: doc, resolutions: { "Alpha Agent" => :rename })

      dr = result.payload[:agents].first
      expect(dr.action).to eq(:renamed)
      expect(dr.record.name).to eq("Alpha Agent-2")
    end

    it "increments suffix when -2 already exists" do
      create(:agent, name: "Alpha Agent",   role: "R")
      create(:agent, name: "Alpha Agent-2", role: "R")
      doc    = build_document(agents: [{ "name" => "Alpha Agent", "role" => "R" }])
      result = described_class.call(document: doc, resolutions: { "Alpha Agent" => :rename })

      expect(result.payload[:agents].first.record.name).to eq("Alpha Agent-3")
    end

    it "wires associations on the renamed agent" do
      skill = create(:skill, name: "coding")
      create(:agent, name: "Alpha Agent", role: "R")
      doc   = build_document(agents: [{
        "name"   => "Alpha Agent",
        "role"   => "R",
        "skills" => ["coding"]
      }])
      result = described_class.call(document: doc, resolutions: { "Alpha Agent" => :rename })
      agent  = result.payload[:agents].first.record

      expect(agent.name).to eq("Alpha Agent-2")
      expect(agent.skills).to match_array([skill])
    end
  end

  # ---------------------------------------------------------------------------
  # Multiple agents
  # ---------------------------------------------------------------------------

  describe "with multiple agents" do
    it "creates all new agents" do
      doc = build_document(agents: [
        { "name" => "Agent One", "role" => "R1" },
        { "name" => "Agent Two", "role" => "R2" }
      ])
      expect { described_class.call(document: doc) }.to change(Agent, :count).by(2)
    end

    it "handles mixed strategies independently" do
      create(:agent, name: "Old Agent", role: "R")
      doc = build_document(agents: [
        { "name" => "Old Agent", "role" => "R" },
        { "name" => "New Agent", "role" => "R" }
      ])
      result  = described_class.call(document: doc, resolutions: { "Old Agent" => :skip })
      actions = result.payload[:agents].map(&:action)

      expect(actions).to eq(%i[skipped created])
    end
  end
end

  # ---------------------------------------------------------------------------
  # Agent config: egress_policy
  # ---------------------------------------------------------------------------

  describe "egress_policy deployment" do
    it "applies egress_policy when present in the agent hash" do
      policy = { "mode" => "allowlist", "rules" => [{ "pattern" => "api.example.com" }] }
      doc    = build_document(agents: [{
        "name"          => "Policy Agent",
        "role"          => "Engineer",
        "egress_policy" => policy
      }])
      agent = described_class.call(document: doc).payload[:agents].first.record
      expect(agent.egress_policy).to include("mode" => "allowlist")
    end

    it "leaves egress_policy blank when not provided" do
      doc   = build_document(agents: [{ "name" => "Plain Agent", "role" => "R" }])
      agent = described_class.call(document: doc).payload[:agents].first.record
      expect(agent.egress_policy).to eq({})
    end

    it "applies egress_policy when overwriting an existing agent" do
      existing = create(:agent, name: "Gated", role: "R", egress_policy: {})
      policy   = { "mode" => "blocklist", "rules" => [] }
      doc      = build_document(agents: [{ "name" => "Gated", "role" => "R", "egress_policy" => policy }])

      described_class.call(document: doc, resolutions: { "Gated" => :overwrite })

      expect(existing.reload.egress_policy).to include("mode" => "blocklist")
    end
  end

  # ---------------------------------------------------------------------------
  # Agent config: tool_loop_config
  # ---------------------------------------------------------------------------

  describe "tool_loop_config deployment" do
    it "applies tool_loop_config when present" do
      config = { "history_size" => 50, "warning_threshold" => 8 }
      doc    = build_document(agents: [{
        "name"             => "Loop Agent",
        "role"             => "Engineer",
        "tool_loop_config" => config
      }])
      agent = described_class.call(document: doc).payload[:agents].first.record
      expect(agent.tool_loop_config).to include("history_size" => 50)
    end

    it "leaves tool_loop_config as default when not provided" do
      doc   = build_document(agents: [{ "name" => "Plain Agent", "role" => "R" }])
      agent = described_class.call(document: doc).payload[:agents].first.record
      expect(agent.tool_loop_config).to eq({})
    end
  end

  # ---------------------------------------------------------------------------
  # Agent config: budget_limits
  # ---------------------------------------------------------------------------

  describe "budget_limits deployment" do
    it "sets daily_budget_limit when provided" do
      doc = build_document(agents: [{
        "name"          => "Budget Agent",
        "role"          => "Engineer",
        "budget_limits" => { "daily_limit" => 25.0 }
      }])
      agent = described_class.call(document: doc).payload[:agents].first.record
      expect(agent.daily_budget_limit.to_f).to eq(25.0)
    end

    it "creates AgentBudget rows from periods" do
      doc = build_document(agents: [{
        "name"          => "Budget Agent",
        "role"          => "Engineer",
        "budget_limits" => {
          "periods" => [
            { "period" => "daily",   "limit_cents" => 1000 },
            { "period" => "monthly", "limit_cents" => 10000 }
          ]
        }
      }])
      agent = described_class.call(document: doc).payload[:agents].first.record
      expect(agent.agent_budgets.count).to eq(2)
    end

    it "does not create AgentBudget rows when budget_limits is absent" do
      doc   = build_document(agents: [{ "name" => "Plain Agent", "role" => "R" }])
      agent = described_class.call(document: doc).payload[:agents].first.record
      expect(agent.agent_budgets).to be_empty
    end
  end
