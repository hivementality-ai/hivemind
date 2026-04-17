# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::SwarmImporter do
  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Minimal valid JSON for a swarm without conflicts.
  def minimal_swarm_json(overrides = {})
    base = {
      "swarm_version" => "1.0",
      "name"          => "Test Swarm"
    }
    base.merge(overrides).to_json
  end

  def full_swarm_json(team_name: "Alpha Team", agent_name: "Alpha Agent",
                      skill_name: "Alpha Skill", tool_name: "alpha-tool")
    {
      "swarm_version" => "1.0",
      "name"          => "Alpha Swarm",
      "team" => {
        "name"        => team_name,
        "description" => "The alpha team"
      },
      "skills" => [
        {
          "name"    => skill_name,
          "summary" => "Does alpha things",
          "content" => "# Alpha skill"
        }
      ],
      "tools" => [
        {
          "name"            => tool_name,
          "description"     => "A tool",
          "script_template" => "echo hello"
        }
      ],
      "agents" => [
        {
          "name"   => agent_name,
          "role"   => "assistant",
          "skills" => [skill_name],
          "tools"  => [tool_name]
        }
      ]
    }.to_json
  end

  # ---------------------------------------------------------------------------
  # Stage 1 — Parse failures
  # ---------------------------------------------------------------------------

  describe "stage 1: parse & validate" do
    it "returns error when json is nil" do
      result = described_class.call(json: nil)
      expect(result).to be_error
      expect(result.payload[:stage]).to eq(:parse)
    end

    it "returns error for invalid JSON" do
      result = described_class.call(json: "not json at all {{{")
      expect(result).to be_error
      expect(result.payload[:stage]).to eq(:parse)
      expect(result.message).to match(/Invalid JSON/i)
    end

    it "returns error when swarm_version is missing" do
      result = described_class.call(json: { "name" => "Oops" }.to_json)
      expect(result).to be_error
      expect(result.payload[:stage]).to eq(:parse)
      expect(result.payload[:errors]).to be_an(Array)
      expect(result.payload[:errors]).not_to be_empty
    end

    it "returns error when name is missing" do
      result = described_class.call(json: { "swarm_version" => "1.0" }.to_json)
      expect(result).to be_error
      expect(result.payload[:stage]).to eq(:parse)
    end
  end

  # ---------------------------------------------------------------------------
  # Stage 2 — Variable resolution failures
  # ---------------------------------------------------------------------------

  describe "stage 2: variable resolution" do
    let(:json_with_required_var) do
      {
        "swarm_version" => "1.0",
        "name"          => "Var Swarm",
        "description"   => "endpoint is {{API_URL}}",
        "variables" => {
          "API_URL" => { "required" => true }
        }
      }.to_json
    end

    it "returns error when a required variable has no value" do
      result = described_class.call(json: json_with_required_var)
      expect(result).to be_error
      expect(result.payload[:stage]).to eq(:variables)
      expect(result.payload[:missing]).to include("API_URL")
    end

    it "succeeds when the required variable is supplied via overrides" do
      result = described_class.call(
        json:               json_with_required_var,
        variable_overrides: { "API_URL" => "https://api.example.com" }
      )
      expect(result).to be_success
    end
  end

  # ---------------------------------------------------------------------------
  # Stage 3 — Vault reference failures
  # ---------------------------------------------------------------------------

  describe "stage 3: vault reference scanning" do
    let(:json_with_vault_ref) do
      {
        "swarm_version" => "1.0",
        "name"          => "Vault Swarm",
        "description"   => "token is vault:slack/bot_token"
      }.to_json
    end

    it "returns error when a vault reference does not exist" do
      result = described_class.call(json: json_with_vault_ref)
      expect(result).to be_error
      expect(result.payload[:stage]).to eq(:vault)
      expect(result.payload[:missing]).to include("slack/bot_token")
    end

    it "succeeds when the vault entry exists" do
      create(:vault_entry, namespace: "slack", key: "bot_token")
      result = described_class.call(json: json_with_vault_ref)
      expect(result).to be_success
    end
  end

  # ---------------------------------------------------------------------------
  # Stage 5 — Entity deployment (happy path)
  # ---------------------------------------------------------------------------

  describe "stage 5: entity deployment — no conflicts" do
    it "returns success" do
      result = described_class.call(json: full_swarm_json)
      expect(result).to be_success
    end

    it "creates one Team" do
      expect { described_class.call(json: full_swarm_json) }.to change(Team, :count).by(1)
    end

    it "creates Skill, Tool, and Agent records" do
      expect {
        described_class.call(json: full_swarm_json)
      }.to change(Skill, :count).by(1)
        .and change(Tool, :count).by(1)
        .and change(Agent, :count).by(1)
    end

    it "wires agent skill association" do
      described_class.call(json: full_swarm_json)
      agent = Agent.find_by(name: "Alpha Agent")
      expect(agent.skills.map(&:name)).to include("Alpha Skill")
    end

    it "wires agent tool association" do
      described_class.call(json: full_swarm_json)
      agent = Agent.find_by(name: "Alpha Agent")
      expect(agent.tools.map(&:name)).to include("alpha-tool")
    end

    it "assigns agent to team" do
      described_class.call(json: full_swarm_json)
      team  = Team.find_by(name: "Alpha Team")
      agent = Agent.find_by(name: "Alpha Agent")
      expect(agent.team).to eq(team)
    end
  end

  # ---------------------------------------------------------------------------
  # ImportReport contract
  # ---------------------------------------------------------------------------

  describe "ImportReport" do
    subject(:report) do
      described_class.call(json: full_swarm_json).payload[:report]
    end

    it "is an ImportReport" do
      expect(report).to be_a(Swarms::SwarmImporter::ImportReport)
    end

    it "holds the imported SwarmDocument" do
      expect(report.document).to be_a(Swarms::SwarmDocument)
      expect(report.document.name).to eq("Alpha Swarm")
    end

    it "has entity_results in deploy order: team → skill → tool → agent" do
      types = report.entity_results.map(&:entity_type)
      expect(types).to eq(%i[team skill tool agent])
    end

    it "marks all entities as :created on a fresh import" do
      actions = report.entity_results.map(&:action).uniq
      expect(actions).to eq([:created])
    end

    it "counts created correctly" do
      expect(report.created_count).to eq(4) # team + skill + tool + agent
    end

    it "returns 0 skipped and updated" do
      expect(report.skipped_count).to eq(0)
      expect(report.updated_count).to eq(0)
    end

    it "summary includes 'created'" do
      expect(report.summary).to match(/created/)
    end

    it "records vault_refs_checked as empty when no vault refs" do
      expect(report.vault_refs_checked).to eq([])
    end

    it "records variable_overrides_applied as empty when no vars" do
      expect(report.variable_overrides_applied).to eq({})
    end

    it "results_for(:agent) returns only agent results" do
      agent_results = report.results_for(:agent)
      expect(agent_results.size).to eq(1)
      expect(agent_results.first.name).to eq("Alpha Agent")
    end
  end

  # ---------------------------------------------------------------------------
  # Report with variable substitution
  # ---------------------------------------------------------------------------

  describe "ImportReport with variable overrides" do
    let(:json_with_var) do
      {
        "swarm_version" => "1.0",
        "name"          => "Var Swarm",
        "team"          => { "name" => "{{TEAM_NAME}}" },
        "variables"     => { "TEAM_NAME" => { "required" => true } }
      }.to_json
    end

    it "records resolved variable values in the report" do
      result = described_class.call(
        json:               json_with_var,
        variable_overrides: { "TEAM_NAME" => "Resolved Team" }
      )
      expect(result).to be_success
      report = result.payload[:report]
      expect(report.variable_overrides_applied["TEAM_NAME"]).to eq("Resolved Team")
    end

    it "creates the team with the resolved name" do
      described_class.call(
        json:               json_with_var,
        variable_overrides: { "TEAM_NAME" => "Resolved Team" }
      )
      expect(Team.exists?(name: "Resolved Team")).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Conflict resolution strategies via resolutions:
  # ---------------------------------------------------------------------------

  describe "conflict resolution" do
    before do
      create(:team, name: "Alpha Team", description: "Old description")
    end

    it "skips the existing team by default (no resolution provided)" do
      expect { described_class.call(json: full_swarm_json) }.not_to change(Team, :count)
    end

    it "overwrites the existing team when resolution is :overwrite" do
      described_class.call(
        json:        full_swarm_json,
        resolutions: { "Alpha Team" => :overwrite }
      )
      expect(Team.find_by(name: "Alpha Team").description).to eq("The alpha team")
    end

    it "renames the incoming team when resolution is :rename" do
      described_class.call(
        json:        full_swarm_json,
        resolutions: { "Alpha Team" => :rename }
      )
      expect(Team.exists?(name: "Alpha Team-2")).to be true
    end

    it "adds conflict warnings to the report" do
      result = described_class.call(json: full_swarm_json)
      report = result.payload[:report]
      expect(report.warnings).not_to be_empty
      expect(report.warnings.first).to match(/Alpha Team.*already exists/i)
    end
  end

  # ---------------------------------------------------------------------------
  # Transaction rollback on deploy failure
  # ---------------------------------------------------------------------------

  describe "transaction rollback" do
    it "rolls back all writes when a deployer raises an error" do
      # Force AgentsDeployer to raise after team/skills/tools have been written.
      allow(Swarms::Deployers::AgentsDeployer).to receive(:call).and_raise(
        RuntimeError, "forced failure"
      )

      expect {
        described_class.call(json: full_swarm_json)
      }.not_to change(Team, :count)

      expect(Skill.count).to eq(0)
      expect(Tool.count).to eq(0)
    end

    it "returns an error ServiceResponse on rollback" do
      allow(Swarms::Deployers::AgentsDeployer).to receive(:call).and_raise(
        RuntimeError, "forced failure"
      )

      result = described_class.call(json: full_swarm_json)
      expect(result).to be_error
      expect(result.payload[:stage]).to eq(:deploy)
    end
  end

  # ---------------------------------------------------------------------------
  # Summary edge cases
  # ---------------------------------------------------------------------------

  describe "ImportReport#summary" do
    it "returns 'nothing deployed' when the swarm has no entities" do
      result = described_class.call(json: minimal_swarm_json)
      expect(result).to be_success
      report = result.payload[:report]
      expect(report.summary).to eq("nothing deployed")
    end

    it "includes renamed count when agents are renamed" do
      create(:agent, name: "Alpha Agent")
      result = described_class.call(
        json:        full_swarm_json,
        resolutions: { "Alpha Agent" => :rename }
      )
      report = result.payload[:report]
      expect(report.summary).to match(/renamed/)
    end
  end
end
