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
      expect(MemoryEntry.for_agent(agent1)).to eq([ entry1 ])
    end

    it ".by_source_type filters by source type" do
      expect(MemoryEntry.by_source_type("Session")).to eq([ entry1 ])
    end
  end

  describe ".search_similar" do
    let(:agent) { create(:agent) }
    # Create entries with real 1536-dim embeddings for vector search
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
      # embedding2 is closest to embedding1
      expect(results.first).to eq(entry1)
    end
  end

  describe ".search_with_threshold" do
    let(:agent) { create(:agent) }
    let(:embedding) { Array.new(768) { |i| (i % 10) * 0.1 } }
    let(:similar_embedding) { Array.new(768) { |i| (i % 10) * 0.1 + 0.001 } }
    let(:different_embedding) { Array.new(768) { rand(-1.0..1.0) } }
    let!(:similar_entry) { create(:memory_entry, agent: agent, embedding: similar_embedding) }
    let!(:different_entry) { create(:memory_entry, agent: agent, embedding: different_embedding) }

    it "filters by similarity threshold" do
      # High threshold should only return very similar entries
      results = MemoryEntry.search_with_threshold(embedding: embedding, agent: agent, threshold: 0.99)
      expect(results).to include(similar_entry)
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
end
