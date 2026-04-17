# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Deployers::TeamDeployer do
  def build_document(team: nil)
    Swarms::SwarmDocument.new(
      swarm_version: "1.0",
      name:          "Test Swarm",
      team:          team
    )
  end

  def team_block(name:, description: nil, custom_soul: nil)
    Swarms::SwarmDocument::SwarmTeam.new(
      name:        name,
      description: description,
      custom_soul: custom_soul
    )
  end

  # ---------------------------------------------------------------------------
  # Result contract
  # ---------------------------------------------------------------------------

  describe "result contract" do
    it "always returns a successful ServiceResponse" do
      doc    = build_document
      result = described_class.call(document: doc)
      expect(result).to be_success
    end

    it "returns nil team when document has no team block" do
      doc    = build_document(team: nil)
      result = described_class.call(document: doc)
      expect(result.payload[:team]).to be_nil
    end

    it "returns nil team when team block has blank name" do
      doc    = build_document(team: team_block(name: ""))
      result = described_class.call(document: doc)
      expect(result.payload[:team]).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # No existing team — create
  # ---------------------------------------------------------------------------

  describe "when no platform team exists with that name" do
    it "creates a new team" do
      doc    = build_document(team: team_block(name: "Alpha Team"))
      expect { described_class.call(document: doc) }.to change(Team, :count).by(1)
    end

    it "returns the created team record" do
      doc    = build_document(team: team_block(name: "Alpha Team", description: "A great team"))
      result = described_class.call(document: doc)
      team   = result.payload[:team]

      expect(team).to be_a(Team)
      expect(team).to be_persisted
      expect(team.name).to eq("Alpha Team")
      expect(team.description).to eq("A great team")
    end

    it "stores custom_soul when provided" do
      doc    = build_document(team: team_block(name: "Soul Team", custom_soul: "Be excellent."))
      result = described_class.call(document: doc)
      expect(result.payload[:team].custom_soul).to eq("Be excellent.")
    end
  end

  # ---------------------------------------------------------------------------
  # Strategy: :skip
  # ---------------------------------------------------------------------------

  describe "strategy :skip" do
    it "returns the existing team without modifying it" do
      existing = create(:team, name: "Existing Team", description: "Old description")
      doc      = build_document(team: team_block(name: "Existing Team", description: "New description"))
      result   = described_class.call(document: doc, resolutions: { team: :skip })

      expect(result.payload[:team]).to eq(existing)
      expect(existing.reload.description).to eq("Old description")
    end

    it "does not create a new team" do
      create(:team, name: "Existing Team")
      doc = build_document(team: team_block(name: "Existing Team"))
      expect { described_class.call(document: doc, resolutions: { team: :skip }) }.not_to change(Team, :count)
    end
  end

  # ---------------------------------------------------------------------------
  # Strategy: :overwrite
  # ---------------------------------------------------------------------------

  describe "strategy :overwrite" do
    it "updates description and custom_soul on the existing team" do
      existing = create(:team, name: "Overwrite Team", description: "Old", custom_soul: nil)
      doc      = build_document(
        team: team_block(name: "Overwrite Team", description: "Updated", custom_soul: "New soul")
      )

      result = described_class.call(document: doc, resolutions: { team: :overwrite })

      expect(result.payload[:team]).to eq(existing)
      expect(existing.reload.description).to eq("Updated")
      expect(existing.reload.custom_soul).to eq("New soul")
    end

    it "does not create an additional team" do
      create(:team, name: "Overwrite Team")
      doc = build_document(team: team_block(name: "Overwrite Team"))
      expect { described_class.call(document: doc, resolutions: { team: :overwrite }) }.not_to change(Team, :count)
    end
  end

  # ---------------------------------------------------------------------------
  # Strategy: :rename
  # ---------------------------------------------------------------------------

  describe "strategy :rename" do
    it "creates a new team with a suffixed name" do
      create(:team, name: "Alpha Team")
      doc    = build_document(team: team_block(name: "Alpha Team"))
      result = described_class.call(document: doc, resolutions: { team: :rename })

      expect(result.payload[:team].name).to eq("Alpha Team-2")
    end

    it "increments the suffix when the suffixed name also exists" do
      create(:team, name: "Alpha Team")
      create(:team, name: "Alpha Team-2")
      doc    = build_document(team: team_block(name: "Alpha Team"))
      result = described_class.call(document: doc, resolutions: { team: :rename })

      expect(result.payload[:team].name).to eq("Alpha Team-3")
    end

    it "creates a new team record" do
      create(:team, name: "Alpha Team")
      doc = build_document(team: team_block(name: "Alpha Team"))
      expect { described_class.call(document: doc, resolutions: { team: :rename }) }.to change(Team, :count).by(1)
    end
  end

  # ---------------------------------------------------------------------------
  # No strategy but conflict present — default to skip
  # ---------------------------------------------------------------------------

  describe "when conflict exists but no resolution strategy is set" do
    it "returns the existing team without modifying it" do
      existing = create(:team, name: "Conflict Team")
      doc      = build_document(team: team_block(name: "Conflict Team"))
      result   = described_class.call(document: doc, resolutions: {})

      expect(result.payload[:team]).to eq(existing)
    end
  end
end
