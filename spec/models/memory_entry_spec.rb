# frozen_string_literal: true

require "rails_helper"

RSpec.describe MemoryEntry, type: :model do
  describe "associations" do
    it { should belong_to(:agent) }
    it { should belong_to(:source).optional }
  end

  describe "validations" do
    it { should validate_presence_of(:content) }
  end

  describe "scopes" do
    let(:agent1) { create(:agent) }
    let(:agent2) { create(:agent) }
    let!(:entry1) { create(:memory_entry, agent: agent1, source_type: "Session") }
    let!(:entry2) { create(:memory_entry, agent: agent2, source_type: "TeamChatMessage") }

    it ".for_agent returns entries for specific agent" do
      expect(MemoryEntry.for_agent(agent1)).to eq([entry1])
    end

    it ".by_source_type filters by source type" do
      expect(MemoryEntry.by_source_type("Session")).to eq([entry1])
    end
  end

  describe ".search_similar" do
    let(:agent) { create(:agent) }
    let!(:entries) { create_list(:memory_entry, 3, agent: agent) }

    it "returns entries for the agent" do
      results = MemoryEntry.search_similar(embedding: [], agent: agent)
      expect(results.count).to eq(3)
    end

    it "respects limit" do
      results = MemoryEntry.search_similar(embedding: [], agent: agent, limit: 2)
      expect(results.count).to eq(2)
    end

    it "orders by created_at desc" do
      results = MemoryEntry.search_similar(embedding: [], agent: agent)
      expect(results).to eq(results.sort_by(&:created_at).reverse)
    end
  end

  describe ".search_with_threshold" do
    let(:agent) { create(:agent) }
    let!(:entries) { create_list(:memory_entry, 2, agent: agent) }

    it "returns entries (delegates to search_similar)" do
      results = MemoryEntry.search_with_threshold(embedding: [], agent: agent)
      expect(results.count).to eq(2)
    end
  end

  describe "#neighbor_distance" do
    it "returns placeholder value" do
      entry = build(:memory_entry)
      expect(entry.neighbor_distance).to eq(0.5)
    end
  end
end
