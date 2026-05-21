# frozen_string_literal: true

require "rails_helper"

RSpec.describe MemoryEntry, type: :model do
  describe "associations" do
    it { should belong_to(:agent) }
    it { should belong_to(:source).optional }
  end

  describe "validations" do
    it { should validate_presence_of(:content) }

    it "validates memory_type inclusion" do
      entry = build(:memory_entry, memory_type: "invalid")
      expect(entry).not_to be_valid
    end

    it "allows valid memory types" do
      %w[episodic semantic procedural preference].each do |type|
        entry = build(:memory_entry, memory_type: type)
        expect(entry).to be_valid
      end
    end
  end

  describe "scopes" do
    let(:agent1) { create(:agent) }
    let(:agent2) { create(:agent) }
    let!(:entry1) { create(:memory_entry, agent: agent1, source_type: "Session", memory_type: "semantic") }
    let!(:entry2) { create(:memory_entry, agent: agent2, source_type: "TeamChatMessage", memory_type: "preference") }
    let!(:entry3) { create(:memory_entry, agent: agent1, memory_type: "episodic", consolidated: true) }

    it ".for_agent returns entries for specific agent" do
      expect(MemoryEntry.for_agent(agent1)).to contain_exactly(entry1, entry3)
    end

    it ".by_source_type filters by source type" do
      expect(MemoryEntry.by_source_type("Session")).to eq([ entry1 ])
    end

    it ".by_type filters by memory type" do
      expect(MemoryEntry.by_type("semantic")).to eq([ entry1 ])
    end

    it ".semantic returns semantic entries" do
      expect(MemoryEntry.semantic).to eq([ entry1 ])
    end

    it ".preferences returns preference entries" do
      expect(MemoryEntry.preferences).to eq([ entry2 ])
    end

    it ".consolidated returns consolidated entries" do
      expect(MemoryEntry.consolidated).to eq([ entry3 ])
    end

    it ".not_consolidated returns non-consolidated entries" do
      expect(MemoryEntry.not_consolidated).to contain_exactly(entry1, entry2)
    end
  end

  describe ".search_similar" do
    let(:agent) { create(:agent) }
    let(:embedding1) { Array.new(768) { |i| (i % 10) * 0.1 } }
    let(:embedding2) { Array.new(768) { |i| (i % 10) * 0.1 + 0.01 } }
    let(:embedding3) { Array.new(768) { |i| (i % 10) * -0.1 } }
    let!(:entry1) { create(:memory_entry, agent: agent, embedding: embedding1) }
    let!(:entry2) { create(:memory_entry, agent: agent, embedding: embedding2) }
    let!(:entry3) { create(:memory_entry, agent: agent, embedding: embedding3) }

    it "returns entries for the agent using vector similarity" do
      results = MemoryEntry.search_similar(embedding: embedding1, agent: agent)
      expect(results.to_a.size).to eq(3)
    end

    it "respects limit" do
      results = MemoryEntry.search_similar(embedding: embedding1, agent: agent, limit: 2)
      expect(results.to_a.size).to eq(2)
    end

    it "returns most similar entries first" do
      results = MemoryEntry.search_similar(embedding: embedding1, agent: agent)
      expect(results.first).to eq(entry1)
    end
  end

  describe ".find_duplicate" do
    let(:agent) { create(:agent) }
    let(:embedding) { Array.new(768) { |i| (i % 10) * 0.1 } }
    let(:near_duplicate) { Array.new(768) { |i| (i % 10) * 0.1 + 0.0001 } }
    let(:different) { Array.new(768) { rand(-1.0..1.0) } }

    let!(:existing_entry) { create(:memory_entry, agent: agent, embedding: embedding) }
    let!(:different_entry) { create(:memory_entry, agent: agent, embedding: different) }

    it "finds near-duplicate entries above threshold" do
      result = MemoryEntry.find_duplicate(embedding: near_duplicate, agent: agent, threshold: 0.99)
      expect(result).to eq(existing_entry)
    end

    it "returns nil when no duplicates exist" do
      # Search with an embedding that's very different from anything stored
      unrelated = Array.new(768) { |i| i.even? ? 1.0 : -1.0 }
      result = MemoryEntry.find_duplicate(embedding: unrelated, agent: agent, threshold: 0.99)
      expect(result).to be_nil
    end
  end

  describe ".relevance_search" do
    let(:agent) { create(:agent) }
    let(:embedding) { Array.new(768) { |i| (i % 10) * 0.1 } }
    let(:similar) { Array.new(768) { |i| (i % 10) * 0.1 + 0.01 } }
    let!(:recent_entry) { create(:memory_entry, agent: agent, embedding: similar, created_at: 1.hour.ago) }
    let!(:old_entry) { create(:memory_entry, agent: agent, embedding: embedding, created_at: 30.days.ago) }

    it "factors in both similarity and recency" do
      results = MemoryEntry.relevance_search(embedding: embedding, agent: agent, limit: 2)
      expect(results).to include(recent_entry)
      expect(results).to include(old_entry)
    end
  end

  describe "#embedded?" do
    let(:agent) { create(:agent) }

    it "returns true when embedding is present" do
      entry = create(:memory_entry, agent: agent, embedding: Array.new(768, 0.1))
      expect(entry.embedded?).to be true
    end

    it "returns false when embedding is nil" do
      entry = create(:memory_entry, agent: agent, embedding: nil)
      expect(entry.embedded?).to be false
    end
  end

  describe "defaults" do
    let(:agent) { create(:agent) }

    it "defaults memory_type to episodic" do
      entry = create(:memory_entry, agent: agent)
      expect(entry.memory_type).to eq("episodic")
    end

    it "defaults importance to 0.5" do
      entry = create(:memory_entry, agent: agent)
      expect(entry.importance).to eq(0.5)
    end

    it "defaults consolidated to false" do
      entry = create(:memory_entry, agent: agent)
      expect(entry.consolidated).to be false
    end
  end
end

# ---- New lifecycle/category specs ----

RSpec.describe MemoryEntry, type: :model do
  describe "category and status validations" do
    let(:agent) { create(:agent) }

    it "defaults category to general" do
      entry = create(:memory_entry, agent: agent)
      expect(entry.category).to eq("general")
    end

    it "defaults status to active" do
      entry = create(:memory_entry, agent: agent)
      expect(entry.status).to eq("active")
    end

    it "rejects invalid categories" do
      entry = build(:memory_entry, agent: agent, category: "invalid_cat")
      expect(entry).not_to be_valid
      expect(entry.errors[:category]).to be_present
    end

    it "rejects invalid statuses" do
      entry = build(:memory_entry, agent: agent, status: "deleted")
      expect(entry).not_to be_valid
      expect(entry.errors[:status]).to be_present
    end

    it "accepts all defined categories" do
      MemoryEntry::CATEGORIES.each do |cat|
        entry = build(:memory_entry, agent: agent, category: cat)
        expect(entry).to be_valid, "expected #{cat} to be valid"
      end
    end

    it "accepts all defined statuses" do
      MemoryEntry::STATUSES.each do |s|
        entry = build(:memory_entry, agent: agent, status: s)
        expect(entry).to be_valid, "expected #{s} to be valid"
      end
    end
  end

  describe "lifecycle scopes" do
    let(:agent) { create(:agent) }
    let!(:active_entry)     { create(:memory_entry, agent: agent, status: "active") }
    let!(:archived_entry)   { create(:memory_entry, agent: agent, status: "archived") }
    let!(:superseded_entry) { create(:memory_entry, agent: agent, status: "superseded") }

    it ".active returns only active entries" do
      expect(MemoryEntry.active).to contain_exactly(active_entry)
    end

    it ".archived returns only archived entries" do
      expect(MemoryEntry.archived).to contain_exactly(archived_entry)
    end

    it ".superseded returns only superseded entries" do
      expect(MemoryEntry.superseded).to contain_exactly(superseded_entry)
    end
  end

  describe "category scope" do
    let(:agent) { create(:agent) }
    let!(:pref_entry)    { create(:memory_entry, agent: agent, category: "user_preference") }
    let!(:context_entry) { create(:memory_entry, agent: agent, category: "project_context") }

    it ".by_category filters by category" do
      expect(MemoryEntry.by_category("user_preference")).to contain_exactly(pref_entry)
    end
  end

  describe "#archive!" do
    let(:agent)     { create(:agent) }
    let!(:entry)    { create(:memory_entry, agent: agent, status: "active") }
    let!(:new_entry) { create(:memory_entry, agent: agent, status: "active") }

    it "sets status to archived" do
      entry.archive!
      expect(entry.reload.status).to eq("archived")
    end

    it "links superseded_by when provided" do
      entry.archive!(superseded_by: new_entry)
      expect(entry.reload.superseded_by_id).to eq(new_entry.id)
    end

    it "does not set superseded_by_id when not provided" do
      entry.archive!
      expect(entry.reload.superseded_by_id).to be_nil
    end
  end

  describe ".search_similar with category/status filters" do
    let(:agent) { create(:agent) }
    let(:embedding) { Array.new(768) { |i| (i % 10) * 0.1 } }
    let!(:active_general)    { create(:memory_entry, agent: agent, embedding: embedding, category: "general",         status: "active") }
    let!(:active_pref)       { create(:memory_entry, agent: agent, embedding: embedding, category: "user_preference", status: "active") }
    let!(:archived_general)  { create(:memory_entry, agent: agent, embedding: embedding, category: "general",         status: "archived") }

    it "defaults to active status only" do
      results = MemoryEntry.search_similar(embedding: embedding, agent: agent, limit: 10)
      expect(results).to include(active_general, active_pref)
      expect(results).not_to include(archived_general)
    end

    it "filters by category" do
      results = MemoryEntry.search_similar(embedding: embedding, agent: agent, limit: 10, category: "user_preference")
      expect(results).to contain_exactly(active_pref)
    end

    it "filters by status when specified" do
      results = MemoryEntry.search_similar(embedding: embedding, agent: agent, limit: 10, status: "archived")
      expect(results).to contain_exactly(archived_general)
    end
  end
end
