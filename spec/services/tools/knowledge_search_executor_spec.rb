# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::KnowledgeSearchExecutor, type: :service do
  let(:agent) { create(:agent) }
  let(:query_embedding) { Array.new(768) { |i| (i % 10) * 0.1 } }
  let(:executor) { described_class.new(input: input, agent: agent) }
  let(:ready_doc) { create(:knowledge_document, agent: agent, status: "ready", title: "Handbook") }

  before { allow(Memory::Embedding).to receive(:generate_query).and_return(query_embedding) }

  describe "#call" do
    let(:input) { { "query" => "vacation policy" } }

    let!(:near)  { create(:knowledge_chunk, knowledge_document: ready_doc, agent: agent, content: "Vacation is 20 days", position: 0, embedding: query_embedding) }
    let!(:far)   { create(:knowledge_chunk, knowledge_document: ready_doc, agent: agent, content: "Office address", position: 1, embedding: Array.new(768) { |i| (i % 10) * -0.1 }) }

    it "returns success" do
      expect(executor.call).to be_success
    end

    it "returns chunks ranked by similarity, closest first" do
      output = executor.call.data[:output]
      expect(output.index(near.content)).to be < output.index(far.content)
    end

    it "includes the document title and match score" do
      output = executor.call.data[:output]
      expect(output).to include("Handbook")
      expect(output).to match(/% match/)
    end

    it "respects the limit" do
      result = described_class.new(input: { "query" => "x", "limit" => 1 }, agent: agent).call
      expect(result.data[:output].scan(/% match/).size).to eq(1)
    end

    it "does not return another agent's chunks" do
      other = create(:agent)
      other_doc = create(:knowledge_document, agent: other, status: "ready")
      create(:knowledge_chunk, knowledge_document: other_doc, agent: other, content: "secret", embedding: query_embedding)
      expect(executor.call.data[:output]).not_to include("secret")
    end
  end

  describe "guard clauses" do
    let(:input) { { "query" => "" } }

    it "fails when query is empty" do
      expect(executor.call).not_to be_success
    end

    it "fails when no agent context" do
      result = described_class.new(input: { "query" => "x" }, agent: nil).call
      expect(result).not_to be_success
    end

    it "reports no results when embedding is unavailable" do
      allow(Memory::Embedding).to receive(:generate_query).and_return(nil)
      result = described_class.new(input: { "query" => "anything" }, agent: agent).call
      expect(result).to be_success
      expect(result.data[:output]).to include("No knowledge base results")
    end
  end
end
