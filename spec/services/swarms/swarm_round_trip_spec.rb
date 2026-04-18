# frozen_string_literal: true

require "rails_helper"

# Full round-trip integration tests for the Swarms import/export pipeline.
#
# Each example exports a configured team to a .swarm.json manifest, then imports
# that manifest into a fresh environment and asserts the resulting database state
# matches the original. Covers:
#
#   - Happy path: all entity types exported and re-imported correctly
#   - Secret stripping & vault reference handling on import
#   - Variable substitution through export -> import
#   - Conflict resolution modes (:skip, :overwrite, :rename)
#   - Invalid schema rejection (bad structure, unknown version)
#   - Partial import rollback on deployer failure
#   - Edge cases: empty teams, missing vault secrets, duplicate entities
#   - Scheduled tasks, heartbeat config round-trip
#   - Egress policy & budget limits round-trip
#   - Multi-agent skill/tool sharing and deduplication
#
RSpec.describe "Swarms round-trip: export to import", type: :integration do
  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  # Export the given team and return the JSON string.
  def export_team(team, **opts)
    result = Swarms::SwarmExporter.call(team: team, **opts)
    expect(result).to be_success, "Export failed: #{result.message}"
    result.payload[:json]
  end

  # Import JSON and return the ServiceResponse.
  def import_json(json, **opts)
    Swarms::SwarmImporter.call(json: json, **opts)
  end

  # Build a hand-crafted JSON blob (no DB records) for import-only tests.
  def static_swarm_json(**overrides)
    base = {
      "swarm_version" => "1.0",
      "name"          => "Static Swarm",
      "team"          => { "name" => "Static Team" },
      "skills"        => [{ "name" => "static-skill", "content" => "# Static", "summary" => "A static skill" }],
      "tools"         => [{ "name" => "static-tool",  "description" => "Static tool",
                            "script_template" => "echo static" }],
      "agents"        => [{
        "name"   => "Static Agent",
        "role"   => "Tester",
        "skills" => ["static-skill"],
        "tools"  => ["static-tool"]
      }]
    }
    base.merge(overrides).to_json
  end

  # ---------------------------------------------------------------------------
  # Fully-configured team fixture
  # ---------------------------------------------------------------------------

  def build_full_team
    team = create(:team, name: "Full Swarm Team", description: "All entity types")

    skill_a = create(:skill, name: "swarm-skill-alpha",
                     content:  "# Alpha\nDoes alpha things.",
                     summary:  "Alpha skill")
    skill_b = create(:skill, name: "swarm-skill-beta",
                     content:  "# Beta\nDoes beta things.",
                     summary:  "Beta skill")
    tool_a  = create(:tool, name: "swarm-tool-alpha",
                     description:     "Alpha tool",
                     script_template: "echo alpha")

    agent_a = create(:agent, name: "Swarm Agent Alpha", role: "Lead",
                     system_prompt: "You are the alpha agent.", team: team)
    agent_a.skills << skill_a
    agent_a.tools  << tool_a

    agent_b = create(:agent, name: "Swarm Agent Beta", role: "Support",
                     system_prompt: "You are the beta agent.", team: team)
    agent_b.skills << skill_a  # shared — tests deduplication
    agent_b.skills << skill_b
    agent_b.tools  << tool_a   # shared — tests deduplication

    { team: team, agents: [agent_a, agent_b], skills: [skill_a, skill_b], tools: [tool_a] }
  end

  # Destroys all DB records created by build_full_team.
  def tear_down_full_team(fixture)
    Agent.where(name: fixture[:agents].map(&:name)).destroy_all
    Skill.where(name: fixture[:skills].map(&:name)).destroy_all
    Tool.where(name:  fixture[:tools].map(&:name)).destroy_all
    fixture[:team].destroy
  end

  # ---------------------------------------------------------------------------
  # 1. Happy path — minimal team (no agents)
  # ---------------------------------------------------------------------------

  describe "minimal team (no agents)" do
    let(:team) { create(:team, name: "Bare Team", description: "Just a team") }

    it "exports without error" do
      result = Swarms::SwarmExporter.call(team: team)
      expect(result).to be_success
    end

    it "produces valid JSON" do
      json = export_team(team)
      expect { JSON.parse(json) }.not_to raise_error
    end

    it "produces a schema-valid manifest" do
      manifest   = Swarms::SwarmExporter.call(team: team).payload[:manifest]
      validation = Swarms::SwarmSchema.validate(manifest)
      expect(validation.valid?).to be true
    end

    it "imports successfully after the original team is removed" do
      json = export_team(team)
      team.destroy
      result = import_json(json)
      expect(result).to be_success
    end

    it "re-creates the team record on import" do
      original_name = team.name
      json          = export_team(team)
      team.destroy
      import_json(json)
      expect(Team.exists?(name: original_name)).to be true
    end

    it "report entity types include :team and nothing else for a bare team" do
      json = export_team(team)
      team.destroy
      result = import_json(json)
      types  = result.payload[:report].entity_results.map(&:entity_type).uniq
      expect(types).to eq([:team])
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Full round-trip — all entity types
  # ---------------------------------------------------------------------------

  describe "full round-trip with all entity types" do
    let!(:fixture) { build_full_team }
    let(:team)     { fixture[:team] }

    it "exports successfully" do
      result = Swarms::SwarmExporter.call(team: team)
      expect(result).to be_success
    end

    it "produces a schema-valid manifest" do
      manifest   = Swarms::SwarmExporter.call(team: team).payload[:manifest]
      validation = Swarms::SwarmSchema.validate(manifest)
      expect(validation.valid?).to be true
    end

    it "manifest includes all agents" do
      manifest    = Swarms::SwarmExporter.call(team: team).payload[:manifest]
      agent_names = manifest["agents"].map { |a| a["name"] }
      expect(agent_names).to include("Swarm Agent Alpha", "Swarm Agent Beta")
    end

    it "manifest deduplicates shared skills" do
      manifest    = Swarms::SwarmExporter.call(team: team).payload[:manifest]
      skill_names = manifest["skills"].map { |s| s["name"] }
      expect(skill_names.tally.values.max).to eq(1), "Duplicate skills found in manifest"
    end

    it "manifest deduplicates shared tools" do
      manifest   = Swarms::SwarmExporter.call(team: team).payload[:manifest]
      tool_names = manifest["tools"].map { |t| t["name"] }
      expect(tool_names.tally.values.max).to eq(1), "Duplicate tools found in manifest"
    end

    context "when imported into a fresh environment" do
      let(:json) { export_team(team) }

      before { tear_down_full_team(fixture) }

      it "succeeds" do
        expect(import_json(json)).to be_success
      end

      it "creates the team" do
        import_json(json)
        expect(Team.exists?(name: "Full Swarm Team")).to be true
      end

      it "creates all skills" do
        import_json(json)
        expect(Skill.where(name: %w[swarm-skill-alpha swarm-skill-beta]).count).to eq(2)
      end

      it "creates all tools" do
        import_json(json)
        expect(Tool.exists?(name: "swarm-tool-alpha")).to be true
      end

      it "creates all agents" do
        import_json(json)
        expect(Agent.where(name: ["Swarm Agent Alpha", "Swarm Agent Beta"]).count).to eq(2)
      end

      it "assigns agents to the team" do
        import_json(json)
        imported_team = Team.find_by!(name: "Full Swarm Team")
        expect(imported_team.agents.count).to eq(2)
      end

      it "restores agent skill associations" do
        import_json(json)
        alpha = Agent.find_by!(name: "Swarm Agent Alpha")
        expect(alpha.skills.map(&:name)).to include("swarm-skill-alpha")
      end

      it "restores agent tool associations" do
        import_json(json)
        alpha = Agent.find_by!(name: "Swarm Agent Alpha")
        expect(alpha.tools.map(&:name)).to include("swarm-tool-alpha")
      end

      it "preserves system_prompt (soul) through the round-trip" do
        import_json(json)
        alpha = Agent.find_by!(name: "Swarm Agent Alpha")
        expect(alpha.system_prompt).to eq("You are the alpha agent.")
      end

      it "marks all entities as :created in the report" do
        result  = import_json(json)
        actions = result.payload[:report].entity_results.map(&:action).uniq
        expect(actions).to eq([:created])
      end

      it "report summary includes 'created'" do
        result = import_json(json)
        expect(result.payload[:report].summary).to match(/created/)
      end

      it "report counts created entities correctly (team + 2 skills + 1 tool + 2 agents = 6)" do
        result = import_json(json)
        expect(result.payload[:report].created_count).to eq(6)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Secret stripping and vault reference handling
  # ---------------------------------------------------------------------------

  describe "secret stripping and vault reference handling" do
    let(:team) { create(:team, name: "Secret Team") }
    let!(:agent) do
      create(:agent, name: "Secret Keeper", role: "Spy", team: team,
             model_config: { "api_key" => "sk-realkey1234567890abcdef" })
    end

    it "strips a long api_key to a vault: reference in the exported manifest" do
      manifest  = Swarms::SwarmExporter.call(team: team).payload[:manifest]
      spy_entry = manifest["agents"].find { |a| a["name"] == "Secret Keeper" }
      api_key   = spy_entry&.dig("model_config", "api_key")
      expect(api_key).to start_with("vault:") if api_key.present?
    end

    it "does not strip secrets when strip_secrets: false" do
      manifest  = Swarms::SwarmExporter.call(team: team, strip_secrets: false).payload[:manifest]
      spy_entry = manifest["agents"].find { |a| a["name"] == "Secret Keeper" }
      api_key   = spy_entry&.dig("model_config", "api_key")
      expect(api_key).to eq("sk-realkey1234567890abcdef") if api_key.present?
    end

    context "importing a manifest with a vault: reference" do
      let(:vault_json) do
        {
          "swarm_version" => "1.0",
          "name"          => "Vault Swarm",
          "description"   => "token is vault:slack/bot_token"
        }.to_json
      end

      it "fails with :vault stage error when the vault entry is missing" do
        result = import_json(vault_json)
        expect(result).to be_error
        expect(result.payload[:stage]).to eq(:vault)
        expect(result.payload[:missing]).to include("slack/bot_token")
      end

      it "succeeds when the vault entry exists" do
        create(:vault_entry, namespace: "slack", key: "bot_token")
        result = import_json(vault_json)
        expect(result).to be_success
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Variable substitution
  # ---------------------------------------------------------------------------

  describe "variable substitution" do
    let(:variable_json) do
      {
        "swarm_version" => "1.0",
        "name"          => "Var Swarm",
        "description"   => "endpoint is {{API_URL}}",
        "team"          => { "name" => "{{TEAM_NAME}} Team" },
        "variables" => {
          "API_URL"   => { "required" => true },
          "TEAM_NAME" => { "required" => true }
        }
      }.to_json
    end

    it "fails with :variables stage error when required variables are missing" do
      result = import_json(variable_json)
      expect(result).to be_error
      expect(result.payload[:stage]).to eq(:variables)
      expect(result.payload[:missing]).to include("API_URL", "TEAM_NAME")
    end

    it "succeeds when all required variables are supplied" do
      result = import_json(variable_json,
                           variable_overrides: { "API_URL" => "https://api.example.com",
                                                 "TEAM_NAME" => "Alpha" })
      expect(result).to be_success
    end

    it "creates the team with the substituted name" do
      import_json(variable_json,
                  variable_overrides: { "API_URL" => "https://api.example.com",
                                        "TEAM_NAME" => "Alpha" })
      expect(Team.exists?(name: "Alpha Team")).to be true
    end

    it "records resolved variable values in the import report" do
      result = import_json(variable_json,
                           variable_overrides: { "API_URL" => "https://api.example.com",
                                                 "TEAM_NAME" => "Alpha" })
      applied = result.payload[:report].variable_overrides_applied
      expect(applied["API_URL"]).to eq("https://api.example.com")
      expect(applied["TEAM_NAME"]).to eq("Alpha")
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Conflict resolution modes
  # ---------------------------------------------------------------------------

  describe "conflict resolution" do
    let!(:fixture) { build_full_team }
    let(:team)     { fixture[:team] }
    let(:json)     { export_team(team) }

    # Second import — original records still exist, so everything conflicts.
    it "skips all conflicting entities by default" do
      result = import_json(json)
      expect(result).to be_success
      report = result.payload[:report]
      expect(report.skipped_count).to be > 0
      expect(report.created_count).to eq(0)
    end

    it "adds conflict warnings to the report when entities already exist" do
      result = import_json(json)
      expect(result.payload[:report].warnings).not_to be_empty
    end

    it "overwrites the existing team when resolution is :overwrite" do
      team.update!(description: "old description")
      import_json(json, resolutions: { "Full Swarm Team" => :overwrite })
      expect(Team.find_by!(name: "Full Swarm Team").description).to eq("All entity types")
    end

    it "renames the incoming agent when resolution is :rename" do
      import_json(json, resolutions: { "Swarm Agent Alpha" => :rename })
      expect(Agent.exists?(name: "Swarm Agent Alpha-2")).to be true
    end

    it "does not duplicate the original record on rename" do
      import_json(json, resolutions: { "Swarm Agent Alpha" => :rename })
      expect(Agent.where(name: "Swarm Agent Alpha").count).to eq(1)
    end

    it "marks renamed entities as :renamed in the report" do
      result  = import_json(json, resolutions: { "Swarm Agent Alpha" => :rename })
      renamed = result.payload[:report].renamed
      expect(renamed.map(&:entity_type)).to include(:agent)
    end

    it "marks overwritten entities as :updated in the report" do
      result  = import_json(json, resolutions: { "Full Swarm Team" => :overwrite })
      updated = result.payload[:report].updated
      expect(updated.map(&:entity_type)).to include(:team)
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Transaction rollback — partial import with failure
  # ---------------------------------------------------------------------------

  describe "transaction rollback on deploy failure" do
    let(:json) { static_swarm_json }

    it "rolls back all writes when AgentsDeployer raises mid-deploy" do
      allow(Swarms::Deployers::AgentsDeployer).to receive(:call)
        .and_raise(RuntimeError, "forced agent failure")

      expect { import_json(json) }.not_to change(Team, :count)
      expect(Skill.exists?(name: "static-skill")).to be false
      expect(Tool.exists?(name: "static-tool")).to be false
    end

    it "returns an error ServiceResponse on rollback" do
      allow(Swarms::Deployers::AgentsDeployer).to receive(:call)
        .and_raise(RuntimeError, "forced agent failure")
      result = import_json(json)
      expect(result).to be_error
      expect(result.payload[:stage]).to eq(:deploy)
    end

    it "rolls back when SkillsDeployer raises early in the pipeline" do
      allow(Swarms::Deployers::SkillsDeployer).to receive(:call)
        .and_raise(RuntimeError, "skills exploded")

      expect { import_json(json) }.not_to change(Team, :count)
      expect(Skill.exists?(name: "static-skill")).to be false
    end

    it "rolls back when ToolsDeployer raises" do
      allow(Swarms::Deployers::ToolsDeployer).to receive(:call)
        .and_raise(RuntimeError, "tools exploded")

      expect { import_json(json) }.not_to change(Agent, :count)
    end
  end

  # ---------------------------------------------------------------------------
  # 7. Invalid schema rejection
  # ---------------------------------------------------------------------------

  describe "invalid schema rejection" do
    it "rejects a document missing swarm_version" do
      result = import_json({ "name" => "Bad Swarm" }.to_json)
      expect(result).to be_error
      expect(result.payload[:stage]).to eq(:parse)
    end

    it "rejects a document missing name" do
      result = import_json({ "swarm_version" => "1.0" }.to_json)
      expect(result).to be_error
      expect(result.payload[:stage]).to eq(:parse)
    end

    it "rejects malformed JSON" do
      result = import_json("not { json } at all")
      expect(result).to be_error
      expect(result.payload[:stage]).to eq(:parse)
      expect(result.message).to match(/invalid json/i)
    end

    it "rejects an agent entry with no name" do
      json = {
        "swarm_version" => "1.0",
        "name"          => "Bad Agent Swarm",
        "agents"        => [{ "role" => "orphan" }]
      }.to_json
      result = import_json(json)
      expect(result).to be_error
      expect(result.payload[:stage]).to eq(:parse)
    end

    it "rejects an agent entry with no role" do
      json = {
        "swarm_version" => "1.0",
        "name"          => "Bad Role Swarm",
        "agents"        => [{ "name" => "No Role" }]
      }.to_json
      result = import_json(json)
      expect(result).to be_error
      expect(result.payload[:stage]).to eq(:parse)
    end

    it "rejects a skill entry with no name" do
      json = {
        "swarm_version" => "1.0",
        "name"          => "Bad Skill Swarm",
        "skills"        => [{ "content" => "no name here" }]
      }.to_json
      result = import_json(json)
      expect(result).to be_error
      expect(result.payload[:stage]).to eq(:parse)
    end

    it "rejects an unknown swarm_version" do
      result = import_json({ "swarm_version" => "99.0", "name" => "Future Swarm" }.to_json)
      expect(result).to be_error
      expect(result.payload[:stage]).to eq(:parse)
    end

    it "the exporter itself validates output and returns error on schema violation" do
      team = create(:team, name: "Validator Team")
      allow(Swarms::SwarmSchema).to receive(:validate).and_return(
        Swarms::SwarmSchema::ValidationResult.new(errors: ["forced schema error"])
      )
      result = Swarms::SwarmExporter.call(team: team)
      expect(result).to be_error
      expect(result.message).to match(/invalid swarm document/i)
    end
  end

  # ---------------------------------------------------------------------------
  # 8. Scheduled tasks round-trip
  # ---------------------------------------------------------------------------

  describe "scheduled tasks round-trip" do
    let(:team)   { create(:team, name: "Scheduled Team") }
    let!(:agent) { create(:agent, name: "Scheduler Agent", role: "Automator", team: team) }
    let!(:task)  do
      create(:scheduled_task,
             agent:    agent,
             name:     "Daily Report",
             schedule: "0 9 * * *",
             prompt:   "Generate daily summary")
    end

    it "exports the scheduled task into the manifest" do
      manifest = Swarms::SwarmExporter.call(team: team).payload[:manifest]
      expect(manifest).to have_key("scheduled_tasks")
      task_names = manifest["scheduled_tasks"].map { |t| t["name"] }
      expect(task_names).to include("Daily Report")
    end

    it "exports the cron schedule correctly" do
      manifest   = Swarms::SwarmExporter.call(team: team).payload[:manifest]
      task_entry = manifest["scheduled_tasks"].find { |t| t["name"] == "Daily Report" }
      expect(task_entry["schedule"]).to eq("0 9 * * *")
    end

    context "when imported into a clean environment" do
      let(:json) { export_team(team) }

      before do
        ScheduledTask.where(name: "Daily Report").destroy_all
        agent.destroy
        team.destroy
      end

      it "re-creates the scheduled task" do
        import_json(json)
        expect(ScheduledTask.exists?(name: "Daily Report")).to be true
      end

      it "preserves the cron schedule" do
        import_json(json)
        imported = ScheduledTask.find_by!(name: "Daily Report")
        expect(imported.schedule).to eq("0 9 * * *")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 9. Heartbeat config round-trip
  # ---------------------------------------------------------------------------

  describe "heartbeat config round-trip" do
    let(:team) { create(:team, name: "Heartbeat Team") }

    before do
      Setting.set("heartbeat", {
        enabled:          true,
        interval_minutes: 30,
        model:            "claude-sonnet",
        provider:         "anthropic",
        prompt:           "Check all systems."
      }.to_json)
    end

    after { Setting.destroy_all }

    it "exports heartbeat config into the manifest" do
      manifest = Swarms::SwarmExporter.call(team: team).payload[:manifest]
      expect(manifest).to have_key("heartbeat_config")
      expect(manifest["heartbeat_config"]["enabled"]).to be true
      expect(manifest["heartbeat_config"]["interval_minutes"]).to eq(30)
    end

    it "imports heartbeat config and applies it to Settings" do
      json = export_team(team)
      team.destroy
      Setting.destroy_all

      import_json(json)

      raw = Setting.get("heartbeat")
      expect(raw).to be_present
      config = JSON.parse(raw)
      expect(config["enabled"]).to be true
      expect(config["interval_minutes"]).to eq(30)
      expect(config["model"]).to eq("claude-sonnet")
    end
  end

  # ---------------------------------------------------------------------------
  # 10. Egress policy round-trip
  # ---------------------------------------------------------------------------

  describe "egress policy round-trip" do
    let(:team) { create(:team, name: "Egress Team") }
    let!(:agent) do
      create(:agent,
             name:          "Egress Agent",
             role:          "Enforcer",
             team:          team,
             egress_policy: {
               "mode"            => "allowlist",
               "allowed_domains" => ["api.example.com", "*.trusted.io"]
             })
    end

    context "when imported into a clean environment" do
      let(:json) { export_team(team, strip_secrets: false) }

      before do
        agent.destroy
        team.destroy
      end

      it "restores the egress policy on the agent" do
        import_json(json)
        imported = Agent.find_by!(name: "Egress Agent")
        policy   = imported.egress_policy.with_indifferent_access
        expect(policy[:mode]).to eq("allowlist")
        expect(policy[:allowed_domains]).to include("api.example.com")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 11. Duplicate entity names within the swarm file
  # ---------------------------------------------------------------------------

  describe "duplicate entity names within the swarm file" do
    it "creates only one skill when the name appears twice" do
      json = {
        "swarm_version" => "1.0",
        "name"          => "Dupe Skill Swarm",
        "skills"        => [
          { "name" => "dupe-skill", "content" => "first" },
          { "name" => "dupe-skill", "content" => "second" }
        ]
      }.to_json
      expect { import_json(json) }.to change(Skill, :count).by(1)
    end

    it "reports the second duplicate skill as :skipped" do
      json = {
        "swarm_version" => "1.0",
        "name"          => "Dupe Skill Swarm 2",
        "skills"        => [
          { "name" => "dupe2-skill", "content" => "first" },
          { "name" => "dupe2-skill", "content" => "second" }
        ]
      }.to_json
      result  = import_json(json)
      actions = result.payload[:report].results_for(:skill).map(&:action)
      expect(actions).to eq(%i[created skipped])
    end

    it "creates only one agent when the name appears twice" do
      json = {
        "swarm_version" => "1.0",
        "name"          => "Dupe Agent Swarm",
        "agents"        => [
          { "name" => "Dupe Agent", "role" => "first" },
          { "name" => "Dupe Agent", "role" => "second" }
        ]
      }.to_json
      expect { import_json(json) }.to change(Agent, :count).by(1)
    end

    it "reports the second duplicate agent as :skipped" do
      json = {
        "swarm_version" => "1.0",
        "name"          => "Dupe Agent Swarm 2",
        "agents"        => [
          { "name" => "Dupe Agent 2", "role" => "first" },
          { "name" => "Dupe Agent 2", "role" => "second" }
        ]
      }.to_json
      result  = import_json(json)
      actions = result.payload[:report].results_for(:agent).map(&:action)
      expect(actions).to eq(%i[created skipped])
    end
  end

  # ---------------------------------------------------------------------------
  # 12. Author metadata in the exported manifest
  # ---------------------------------------------------------------------------

  describe "author metadata" do
    let(:team) { create(:team, name: "Authored Team") }

    it "includes author when name and email are provided" do
      manifest = Swarms::SwarmExporter.call(
        team:         team,
        author_name:  "Mando",
        author_email: "mando@example.com"
      ).payload[:manifest]
      expect(manifest["author"]).to eq({ "name" => "Mando", "email" => "mando@example.com" })
    end

    it "omits author when no name is provided" do
      manifest = Swarms::SwarmExporter.call(team: team).payload[:manifest]
      expect(manifest).not_to have_key("author")
    end

    it "omits author when only email is provided (schema requires author.name)" do
      manifest = Swarms::SwarmExporter.call(team: team, author_email: "noreply@example.com").payload[:manifest]
      expect(manifest).not_to have_key("author")
    end
  end

  # ---------------------------------------------------------------------------
  # 13. Multi-agent skill and tool sharing
  # ---------------------------------------------------------------------------

  describe "multi-agent skill and tool sharing" do
    let(:team)         { create(:team, name: "Shared Resources Team") }
    let(:shared_skill) { create(:skill, name: "shared-skill", content: "# Shared", summary: "Shared") }
    let(:shared_tool)  { create(:tool,  name: "shared-tool",  description: "Shared",
                                        script_template: "echo shared") }
    let!(:agents) do
      3.times.map do |i|
        a = create(:agent, name: "Multi Agent #{i}", role: "Member", team: team)
        a.skills << shared_skill
        a.tools  << shared_tool
        a
      end
    end

    it "exports each shared entity exactly once" do
      manifest = Swarms::SwarmExporter.call(team: team).payload[:manifest]
      expect(manifest["skills"].count { |s| s["name"] == "shared-skill" }).to eq(1)
      expect(manifest["tools"].count  { |t| t["name"] == "shared-tool"  }).to eq(1)
    end

    it "each agent in the manifest references the shared skill" do
      manifest         = Swarms::SwarmExporter.call(team: team).payload[:manifest]
      agents_with_skill = manifest["agents"].select { |a| Array(a["skills"]).include?("shared-skill") }
      expect(agents_with_skill.size).to eq(3)
    end

    it "each agent references the shared tool" do
      manifest        = Swarms::SwarmExporter.call(team: team).payload[:manifest]
      agents_with_tool = manifest["agents"].select { |a| Array(a["tools"]).include?("shared-tool") }
      expect(agents_with_tool.size).to eq(3)
    end
  end

  # ---------------------------------------------------------------------------
  # 14. Import report entity ordering
  # ---------------------------------------------------------------------------

  describe "import report entity ordering" do
    let(:json) do
      {
        "swarm_version" => "1.0",
        "name"          => "Ordered Swarm",
        "team"          => { "name" => "Ordered Team" },
        "skills"        => [{ "name" => "order-skill", "content" => "# S", "summary" => "S" }],
        "tools"         => [{ "name" => "order-tool",  "description" => "T",
                              "script_template" => "echo order" }],
        "agents"        => [{ "name" => "Order Agent", "role" => "Member",
                              "skills" => ["order-skill"], "tools" => ["order-tool"] }]
      }.to_json
    end

    it "entity_results arrive in deploy order: team -> skill -> tool -> agent" do
      result = import_json(json)
      types  = result.payload[:report].entity_results.map(&:entity_type)
      expect(types).to eq(%i[team skill tool agent])
    end

    it "vault_refs_checked is empty when no vault references are present" do
      result = import_json(json)
      expect(result.payload[:report].vault_refs_checked).to eq([])
    end

    it "variable_overrides_applied is empty when no variables are defined" do
      result = import_json(json)
      expect(result.payload[:report].variable_overrides_applied).to eq({})
    end
  end

  # ---------------------------------------------------------------------------
  # 15. Export error handling
  # ---------------------------------------------------------------------------

  describe "export error handling" do
    let(:team) { create(:team, name: "Error Team") }

    it "returns an error ServiceResponse when a serializer raises" do
      allow(Swarms::Serializers::TeamSerializer).to receive(:call).and_raise(RuntimeError, "serializer exploded")
      result = Swarms::SwarmExporter.call(team: team)
      expect(result).to be_error
      expect(result.message).to match(/Export failed/i)
    end

    it "the error message is informative" do
      allow(Swarms::Serializers::TeamSerializer).to receive(:call).and_raise(RuntimeError, "serializer exploded")
      result = Swarms::SwarmExporter.call(team: team)
      expect(result.message).to include("serializer exploded")
    end
  end
end
