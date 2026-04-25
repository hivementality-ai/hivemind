# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::SwarmExporter do
  # ---------------------------------------------------------------------------
  # Test data setup
  # ---------------------------------------------------------------------------

  let(:team)  { create(:team, name: "Mandalorian Squad", description: "A tight-knit crew") }
  let(:skill) { create(:skill, name: "Combat Tactics", content: "# Combat\n\nKnow your enemy.") }
  let(:tool)  { create(:tool, name: "Blaster", description: "Ranged weapon tool") }

  let(:agent) do
    create(:agent,
      name:          "Din Djarin",
      role:          "Bounty Hunter",
      system_prompt: "You protect the asset.",
      team:          team,
      llm_model:     "claude-opus-4-5"
    )
  end

  def call(**opts)
    described_class.call(team: team, **opts)
  end

  # ---------------------------------------------------------------------------
  # Result contract
  # ---------------------------------------------------------------------------

  describe "result contract" do
    it "returns a successful ServiceResponse for a team with no agents" do
      result = call
      expect(result).to be_success
    end

    it "payload includes manifest, json, filename, and stripped_paths" do
      result = call
      expect(result.payload).to include(:manifest, :json, :filename, :stripped_paths)
    end

    it "json is valid parseable JSON" do
      result = call
      expect { JSON.parse(result.payload[:json]) }.not_to raise_error
    end

    it "filename uses the team name parameterized with .swarm.json extension" do
      result = call
      expect(result.payload[:filename]).to eq("mandalorian_squad.swarm.json")
    end
  end

  # ---------------------------------------------------------------------------
  # Manifest structure
  # ---------------------------------------------------------------------------

  describe "manifest top-level metadata" do
    it "sets swarm_version to 1.0" do
      manifest = call.payload[:manifest]
      expect(manifest["swarm_version"]).to eq("1.0")
    end

    it "sets name from team" do
      manifest = call.payload[:manifest]
      expect(manifest["name"]).to eq("Mandalorian Squad")
    end

    it "includes exported_at as ISO8601 timestamp" do
      manifest = call.payload[:manifest]
      expect(manifest["exported_at"]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
    end

    it "includes description from team when not overridden" do
      manifest = call.payload[:manifest]
      expect(manifest["description"]).to eq("A tight-knit crew")
    end

    it "overrides description when provided" do
      manifest = call(description: "Custom desc").payload[:manifest]
      expect(manifest["description"]).to eq("Custom desc")
    end

    it "omits author when no author params given" do
      manifest = call.payload[:manifest]
      expect(manifest).not_to have_key("author")
    end

    it "includes author when author_name is provided" do
      manifest = call(author_name: "Alice").payload[:manifest]
      expect(manifest["author"]).to eq({ "name" => "Alice" })
    end

    it "includes author with name and email when both provided" do
      manifest = call(author_name: "Alice", author_email: "alice@example.com").payload[:manifest]
      expect(manifest["author"]).to eq({ "name" => "Alice", "email" => "alice@example.com" })
    end

    it "omits author when only email is provided (schema requires author.name)" do
      manifest = call(author_email: "alice@example.com").payload[:manifest]
      expect(manifest).not_to have_key("author")
    end
  end

  # ---------------------------------------------------------------------------
  # Entity serialization
  # ---------------------------------------------------------------------------

  describe "team serialization" do
    it "includes team block with name" do
      manifest = call.payload[:manifest]
      expect(manifest["team"]).to include("name" => "Mandalorian Squad")
    end
  end

  describe "agent serialization" do
    before { agent } # create agent

    it "includes the agent in agents array" do
      manifest = call.payload[:manifest]
      agent_hashes = manifest["agents"]
      expect(agent_hashes).to be_an(Array)
      expect(agent_hashes.map { |a| a["name"] }).to include("Din Djarin")
    end

    it "agent hash includes required fields" do
      manifest    = call.payload[:manifest]
      agent_entry = manifest["agents"].find { |a| a["name"] == "Din Djarin" }
      expect(agent_entry["role"]).to eq("Bounty Hunter")
      expect(agent_entry["soul"]).to eq("You protect the asset.")
    end
  end

  describe "skill serialization" do
    before do
      agent.skills << skill
    end

    it "includes the skill in skills array" do
      manifest = call.payload[:manifest]
      expect(manifest["skills"].map { |s| s["name"] }).to include("Combat Tactics")
    end

    it "deduplicates skills referenced by multiple agents" do
      agent2 = create(:agent, name: "Grogu", role: "Padawan", team: team)
      agent2.skills << skill
      manifest = call.payload[:manifest]
      expect(manifest["skills"].map { |s| s["name"] }.tally.values.max).to eq(1)
    end
  end

  describe "tool serialization" do
    before do
      agent.tools << tool
    end

    it "includes the tool in tools array" do
      manifest = call.payload[:manifest]
      expect(manifest["tools"].map { |t| t["name"] }).to include("Blaster")
    end
  end

  describe "empty teams" do
    it "omits agents key when team has no agents" do
      manifest = call.payload[:manifest]
      expect(manifest).not_to have_key("agents")
    end

    it "omits skills key when no agents have skills" do
      manifest = call.payload[:manifest]
      expect(manifest).not_to have_key("skills")
    end
  end

  # ---------------------------------------------------------------------------
  # Secret stripping
  # ---------------------------------------------------------------------------

  describe "secret stripping (default on)" do
    it "strips secrets from the manifest by default" do
      # Create an agent whose model_config contains an api_key
      agent_with_secret = create(:agent,
        name:        "Secret Agent",
        role:        "Spy",
        team:        team,
        model_config: { "api_key" => "sk-verylongsecretvalue123456789" }
      )
      manifest = call.payload[:manifest]
      spy_entry = manifest["agents"]&.find { |a| a["name"] == "Secret Agent" }
      # The api_key inside model_config should be stripped
      expect(spy_entry["model_config"]["api_key"]).to start_with("vault:") if spy_entry&.dig("model_config", "api_key")
    end

    it "does not strip when strip_secrets: false" do
      agent_with_secret = create(:agent,
        name:        "Secret Agent",
        role:        "Spy",
        team:        team,
        model_config: { "api_key" => "sk-verylongsecretvalue123456789" }
      )
      manifest = call(strip_secrets: false).payload[:manifest]
      spy_entry = manifest["agents"]&.find { |a| a["name"] == "Secret Agent" }
      expect(spy_entry["model_config"]["api_key"]).to eq("sk-verylongsecretvalue123456789") if spy_entry&.dig("model_config", "api_key")
    end
  end

  # ---------------------------------------------------------------------------
  # Schema validation
  # ---------------------------------------------------------------------------

  describe "schema validation" do
    it "produces a schema-valid manifest" do
      validation = Swarms::SwarmSchema.validate(call.payload[:manifest])
      expect(validation.valid?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------

  describe "error handling" do
    it "returns an error ServiceResponse when something raises" do
      allow(Swarms::Serializers::TeamSerializer).to receive(:call).and_raise(RuntimeError, "boom")
      result = call
      expect(result).to be_error
      expect(result.message).to include("Export failed")
    end
  end
end
