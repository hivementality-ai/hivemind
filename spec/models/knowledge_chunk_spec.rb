# frozen_string_literal: true

require "rails_helper"

RSpec.describe KnowledgeChunk, type: :model do
  describe "associations" do
    it { should belong_to(:knowledge_document) }
    it { should belong_to(:agent) }
  end

  describe "validations" do
    it { should validate_presence_of(:content) }
  end

  describe "pgvector embedding column" do
    let(:agent) { create(:agent) }
    let(:embedding) { Array.new(768) { |i| (i % 10) * 0.1 } }

    it "stores and reads back a 768-dim vector" do
      chunk = create(:knowledge_chunk, agent: agent, embedding: embedding)
      stored = chunk.reload.embedding.map(&:to_f)
      expect(stored.size).to eq(768) # pgvector stores float32, so compare with tolerance
      stored.each_with_index { |v, i| expect(v).to be_within(1e-5).of(embedding[i]) }
      expect(chunk.embedded?).to be true
    end
  end

  describe ".search_similar" do
    let(:agent) { create(:agent) }
    let(:other_agent) { create(:agent) }
    let(:embedding1) { Array.new(768) { |i| (i % 10) * 0.1 } }
    let(:embedding2) { Array.new(768) { |i| (i % 10) * 0.1 + 0.01 } }
    let(:embedding3) { Array.new(768) { |i| (i % 10) * -0.1 } }
    let(:ready_doc) { create(:knowledge_document, agent: agent, status: "ready") }

    let!(:chunk1) { create(:knowledge_chunk, knowledge_document: ready_doc, agent: agent, embedding: embedding1) }
    let!(:chunk2) { create(:knowledge_chunk, knowledge_document: ready_doc, agent: agent, embedding: embedding2) }
    let!(:chunk3) { create(:knowledge_chunk, knowledge_document: ready_doc, agent: agent, embedding: embedding3) }

    it "returns chunks ranked by cosine similarity" do
      results = KnowledgeChunk.search_similar(embedding: embedding1, agent: agent)
      expect(results.first).to eq(chunk1)
    end

    it "respects the limit" do
      results = KnowledgeChunk.search_similar(embedding: embedding1, agent: agent, limit: 2)
      expect(results.size).to eq(2)
    end

    it "scopes to the agent" do
      other_doc = create(:knowledge_document, agent: other_agent, status: "ready")
      create(:knowledge_chunk, knowledge_document: other_doc, agent: other_agent, embedding: embedding1)
      results = KnowledgeChunk.search_similar(embedding: embedding1, agent: agent)
      expect(results.map(&:agent_id).uniq).to eq([ agent.id ])
    end

    it "excludes chunks from non-ready documents" do
      pending_doc = create(:knowledge_document, agent: agent, status: "pending")
      hidden = create(:knowledge_chunk, knowledge_document: pending_doc, agent: agent, embedding: embedding1)
      results = KnowledgeChunk.search_similar(embedding: embedding1, agent: agent)
      expect(results).not_to include(hidden)
    end
  end
end
