# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::SwarmConflictDetector do
  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def build_document(overrides = {})
    defaults = {
      swarm_version: "1.0",
      name:          "Test Swarm",
      team:          nil,
      agents:        [],
      skills:        [],
      tools:         [],
      channels:      [],
      mcp_servers:   []
    }
    Swarms::SwarmDocument.new(**defaults.merge(overrides))
  end

  def team_block(name:)
    Swarms::SwarmDocument::SwarmTeam.new(name: name, description: nil, custom_soul: nil)
  end

  # ---------------------------------------------------------------------------
  # Result contract
  # ---------------------------------------------------------------------------

  describe "result contract" do
    it "always returns a successful ServiceResponse" do
      result = described_class.call(document: build_document)
      expect(result).to be_success
    end

    it "payload is a ConflictReport" do
      result = described_class.call(document: build_document)
      expect(result.payload).to be_a(Swarms::SwarmConflictDetector::ConflictReport)
    end

    it "returns an empty report when swarm document has no entities" do
      report = described_class.call(document: build_document).payload
      expect(report.none?).to be true
      expect(report.count).to eq(0)
      expect(report.conflicts).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Team conflicts
  # ---------------------------------------------------------------------------

  describe "team conflict detection" do
    context "when the swarm has no team block" do
      it "reports no conflict" do
        doc    = build_document(team: nil)
        report = described_class.call(document: doc).payload
        expect(report.conflicts_for(:team)).to be_empty
      end
    end

    context "when no platform team exists with that name" do
      it "reports no conflict" do
        doc    = build_document(team: team_block(name: "Brand New Team"))
        report = described_class.call(document: doc).payload
        expect(report.conflicts_for(:team)).to be_empty
      end
    end

    context "when a platform team already has the same name" do
      it "reports a :team conflict" do
        create(:team, name: "Existing Team")
        doc    = build_document(team: team_block(name: "Existing Team"))
        report = described_class.call(document: doc).payload

        expect(report.conflicts_for(:team).size).to eq(1)
        conflict = report.conflicts_for(:team).first
        expect(conflict.entity_type).to eq(:team)
        expect(conflict.name).to eq("Existing Team")
        expect(conflict.swarm_index).to eq(0)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Agent conflicts
  # ---------------------------------------------------------------------------

  describe "agent conflict detection" do
    context "when swarm has no agents" do
      it "reports no agent conflicts" do
        report = described_class.call(document: build_document(agents: [])).payload
        expect(report.conflicts_for(:agents)).to be_empty
      end
    end

    context "when no platform agent matches any swarm agent name" do
      it "reports no agent conflicts" do
        doc    = build_document(agents: [{ "name" => "Unique Agent" }])
        report = described_class.call(document: doc).payload
        expect(report.conflicts_for(:agents)).to be_empty
      end
    end

    context "when one swarm agent name matches an existing platform agent" do
      it "reports one :agents conflict" do
        create(:agent, name: "Alpha Agent")
        doc    = build_document(agents: [
          { "name" => "Alpha Agent" },
          { "name" => "Beta Agent" }
        ])
        report = described_class.call(document: doc).payload

        agent_conflicts = report.conflicts_for(:agents)
        expect(agent_conflicts.size).to eq(1)
        expect(agent_conflicts.first.name).to eq("Alpha Agent")
        expect(agent_conflicts.first.swarm_index).to eq(0)
      end
    end

    context "when multiple swarm agents conflict" do
      it "reports all colliding agents" do
        create(:agent, name: "Alpha Agent")
        create(:agent, name: "Gamma Agent")
        doc    = build_document(agents: [
          { "name" => "Alpha Agent" },
          { "name" => "Beta Agent" },
          { "name" => "Gamma Agent" }
        ])
        report = described_class.call(document: doc).payload

        agent_conflicts = report.conflicts_for(:agents)
        expect(agent_conflicts.size).to eq(2)
        expect(agent_conflicts.map(&:name)).to contain_exactly("Alpha Agent", "Gamma Agent")
        expect(agent_conflicts.map(&:swarm_index)).to contain_exactly(0, 2)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Skill conflicts
  # ---------------------------------------------------------------------------

  describe "skill conflict detection" do
    context "when a skill name collides" do
      it "reports a :skills conflict with the correct index" do
        create(:skill, name: "existing-skill")
        doc    = build_document(skills: [
          { "name" => "new-skill" },
          { "name" => "existing-skill" }
        ])
        report = described_class.call(document: doc).payload

        skill_conflicts = report.conflicts_for(:skills)
        expect(skill_conflicts.size).to eq(1)
        expect(skill_conflicts.first.name).to eq("existing-skill")
        expect(skill_conflicts.first.swarm_index).to eq(1)
      end
    end

    context "when no skill names collide" do
      it "reports no skill conflicts" do
        doc    = build_document(skills: [{ "name" => "fresh-skill" }])
        report = described_class.call(document: doc).payload
        expect(report.conflicts_for(:skills)).to be_empty
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Tool conflicts
  # ---------------------------------------------------------------------------

  describe "tool conflict detection" do
    context "when a tool name collides" do
      it "reports a :tools conflict" do
        create(:tool, name: "existing-tool")
        doc    = build_document(tools: [{ "name" => "existing-tool" }])
        report = described_class.call(document: doc).payload

        tool_conflicts = report.conflicts_for(:tools)
        expect(tool_conflicts.size).to eq(1)
        expect(tool_conflicts.first.name).to eq("existing-tool")
        expect(tool_conflicts.first.swarm_index).to eq(0)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Channel conflicts
  # ---------------------------------------------------------------------------

  describe "channel conflict detection" do
    context "when a channel name collides" do
      it "reports a :channels conflict" do
        create(:channel, name: "main-slack")
        doc    = build_document(channels: [
          { "name" => "main-slack", "ref" => "main-slack", "type" => "slack" }
        ])
        report = described_class.call(document: doc).payload

        channel_conflicts = report.conflicts_for(:channels)
        expect(channel_conflicts.size).to eq(1)
        expect(channel_conflicts.first.name).to eq("main-slack")
      end
    end

    context "when no channel names collide" do
      it "reports no channel conflicts" do
        doc    = build_document(channels: [{ "name" => "fresh-channel" }])
        report = described_class.call(document: doc).payload
        expect(report.conflicts_for(:channels)).to be_empty
      end
    end
  end

  # ---------------------------------------------------------------------------
  # MCP server conflicts
  # ---------------------------------------------------------------------------

  describe "mcp_server conflict detection" do
    context "when an mcp_server name collides" do
      it "reports a :mcp_servers conflict" do
        create(:mcp_server, name: "my-mcp")
        doc    = build_document(mcp_servers: [{ "name" => "my-mcp" }])
        report = described_class.call(document: doc).payload

        mcp_conflicts = report.conflicts_for(:mcp_servers)
        expect(mcp_conflicts.size).to eq(1)
        expect(mcp_conflicts.first.name).to eq("my-mcp")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-type conflicts
  # ---------------------------------------------------------------------------

  describe "cross-type conflict detection" do
    it "detects conflicts across multiple entity types in one call" do
      create(:skill, name: "shared-skill")
      create(:tool,  name: "shared-tool")

      doc = build_document(
        skills: [{ "name" => "shared-skill" }, { "name" => "other-skill" }],
        tools:  [{ "name" => "shared-tool" }]
      )
      report = described_class.call(document: doc).payload

      expect(report.any?).to be true
      expect(report.count).to eq(2)
      expect(report.conflicts_for(:skills).map(&:name)).to eq(["shared-skill"])
      expect(report.conflicts_for(:tools).map(&:name)).to eq(["shared-tool"])
    end

    it "groups conflicts by type via by_type" do
      create(:skill, name: "s1")
      create(:tool,  name: "t1")

      doc    = build_document(
        skills: [{ "name" => "s1" }],
        tools:  [{ "name" => "t1" }]
      )
      by_type = described_class.call(document: doc).payload.by_type

      expect(by_type.keys).to contain_exactly(:skills, :tools)
      expect(by_type[:skills].first.name).to eq("s1")
      expect(by_type[:tools].first.name).to eq("t1")
    end
  end

  # ---------------------------------------------------------------------------
  # Conflict value object
  # ---------------------------------------------------------------------------

  describe Swarms::SwarmConflictDetector::Conflict do
    subject(:conflict) do
      described_class.new(entity_type: :skills, name: "my-skill", swarm_index: 2)
    end

    it "exposes entity_type, name, and swarm_index" do
      expect(conflict.entity_type).to eq(:skills)
      expect(conflict.name).to eq("my-skill")
      expect(conflict.swarm_index).to eq(2)
    end

    it "exposes all three resolution strategies" do
      expect(conflict.resolution_strategies).to contain_exactly(:skip, :rename, :overwrite)
    end
  end

  # ---------------------------------------------------------------------------
  # ConflictReport value object
  # ---------------------------------------------------------------------------

  describe Swarms::SwarmConflictDetector::ConflictReport do
    let(:c1) { Swarms::SwarmConflictDetector::Conflict.new(entity_type: :skills, name: "s1", swarm_index: 0) }
    let(:c2) { Swarms::SwarmConflictDetector::Conflict.new(entity_type: :tools,  name: "t1", swarm_index: 1) }

    subject(:report) { described_class.new(conflicts: [c1, c2]) }

    it "reports any? as true when there are conflicts" do
      expect(report.any?).to be true
    end

    it "reports none? as false when there are conflicts" do
      expect(report.none?).to be false
    end

    it "count returns the number of conflicts" do
      expect(report.count).to eq(2)
    end

    it "filters by entity type" do
      expect(report.conflicts_for(:skills)).to eq([c1])
      expect(report.conflicts_for(:tools)).to eq([c2])
    end

    it "groups by type" do
      expect(report.by_type).to eq({ skills: [c1], tools: [c2] })
    end

    context "with no conflicts" do
      subject(:empty_report) { described_class.new(conflicts: []) }

      it "any? is false" do
        expect(empty_report.any?).to be false
      end

      it "none? is true" do
        expect(empty_report.none?).to be true
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  describe "edge cases" do
    it "skips entities with blank names" do
      doc    = build_document(skills: [{ "name" => "" }, { "name" => nil }])
      report = described_class.call(document: doc).payload
      expect(report.conflicts_for(:skills)).to be_empty
    end

    it "skips non-Hash entries in entity arrays" do
      doc    = build_document(tools: ["bad-entry", 42, nil])
      report = described_class.call(document: doc).payload
      expect(report.conflicts_for(:tools)).to be_empty
    end

    it "is case-sensitive — different case is not a conflict" do
      create(:skill, name: "My-Skill")
      doc    = build_document(skills: [{ "name" => "my-skill" }])
      report = described_class.call(document: doc).payload
      expect(report.conflicts_for(:skills)).to be_empty
    end
  end
end
