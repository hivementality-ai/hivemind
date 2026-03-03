# frozen_string_literal: true

require "rails_helper"

RSpec.describe OpenClaw::MemoryParser do
  let(:agent) { create(:agent) }
  let(:workspace_path) do
    create_openclaw_workspace(
      memory: "## Preferences\nUser prefers Ruby over Python.\n\n## Workflow\nAlways run bundle install first.",
      daily_memories: {
        "2024-01-15.md" => "## Morning\nDeployed new version to production."
      }
    )
  end

  after { cleanup_openclaw_workspace(workspace_path) }

  describe ".call" do
    it "imports memories from MEMORY.md" do
      result = described_class.call(workspace_path: workspace_path, agent: agent)

      expect(result).to be_success
      expect(result.data[:count]).to eq(3)
      expect(result.data[:files_processed]).to eq(2)
    end

    it "creates MemoryEntry records with correct metadata" do
      described_class.call(workspace_path: workspace_path, agent: agent)

      entries = MemoryEntry.where(agent: agent)
      expect(entries.count).to eq(3)

      preference_entry = entries.find { |e| e.content.include?("Ruby") }
      expect(preference_entry.memory_type).to eq("preference")
      expect(preference_entry.metadata["imported_from"]).to eq("openclaw")
      expect(preference_entry.metadata["source_file"]).to eq("MEMORY.md")
      expect(preference_entry.metadata["section"]).to eq("Preferences")
    end

    it "enqueues MemoryEmbeddingJob for each entry" do
      described_class.call(workspace_path: workspace_path, agent: agent)

      expect(MemoryEmbeddingJob).to have_been_enqueued.exactly(3).times
    end

    it "skips embedding jobs in dry_run mode" do
      described_class.call(workspace_path: workspace_path, agent: agent, dry_run: true)

      expect(MemoryEmbeddingJob).not_to have_been_enqueued
    end

    it "skips chunks shorter than 20 characters" do
      path = create_openclaw_workspace(memory: "## Tiny\nHi.\n\n## Real\nThis is a properly sized memory chunk.")
      result = described_class.call(workspace_path: path, agent: agent)

      expect(result.data[:count]).to eq(1)
      cleanup_openclaw_workspace(path)
    end

    it "imports daily memory files" do
      described_class.call(workspace_path: workspace_path, agent: agent)

      daily_entry = MemoryEntry.find_by(agent: agent, metadata: { "source_file" => "memory/2024-01-15.md" }.to_json)
        .presence || MemoryEntry.where(agent: agent).find { |e| e.metadata["source_file"]&.include?("2024-01-15") }

      expect(daily_entry).to be_present
      expect(daily_entry.content).to include("Deployed")
    end

    context "without MEMORY.md" do
      let(:workspace_path) { create_openclaw_workspace(memory: nil) }

      it "returns zero count" do
        result = described_class.call(workspace_path: workspace_path, agent: agent)

        expect(result).to be_success
        expect(result.data[:count]).to eq(0)
      end
    end

    it "guesses memory types correctly" do
      path = create_openclaw_workspace(memory: <<~MD)
        ## Prefs
        I always use dark mode and prefer vim keybindings.

        ## Facts
        My name is Matt and works at Acme Corp.

        ## How-to
        Run docker compose up to start the dev environment.

        ## Events
        We launched the new feature last Tuesday.
      MD

      described_class.call(workspace_path: path, agent: agent)

      entries = MemoryEntry.where(agent: agent).order(:id)
      types = entries.map(&:memory_type)
      expect(types).to eq(%w[preference semantic procedural episodic])

      cleanup_openclaw_workspace(path)
    end
  end
end
