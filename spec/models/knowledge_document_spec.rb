# frozen_string_literal: true

require "rails_helper"

RSpec.describe KnowledgeDocument, type: :model do
  describe "associations" do
    it { should belong_to(:agent) }
    it { should have_many(:chunks).dependent(:destroy) }
  end

  describe "validations" do
    it { should validate_presence_of(:title) }

    it "validates source_type inclusion" do
      doc = build(:knowledge_document, source_type: "video")
      expect(doc).not_to be_valid
      expect(doc.errors[:source_type]).to be_present
    end

    it "validates status inclusion" do
      doc = build(:knowledge_document, status: "deleted")
      expect(doc).not_to be_valid
      expect(doc.errors[:status]).to be_present
    end

    it "allows all valid statuses" do
      %w[pending processing ready failed].each do |st|
        expect(build(:knowledge_document, status: st)).to be_valid
      end
    end
  end

  describe "scopes" do
    let(:agent1) { create(:agent) }
    let(:agent2) { create(:agent) }
    let!(:ready_doc)   { create(:knowledge_document, agent: agent1, status: "ready") }
    let!(:pending_doc) { create(:knowledge_document, agent: agent1, status: "pending") }
    let!(:other_doc)   { create(:knowledge_document, agent: agent2, status: "ready") }

    it ".for_agent scopes to the agent" do
      expect(KnowledgeDocument.for_agent(agent1)).to contain_exactly(ready_doc, pending_doc)
    end

    it ".ready returns only ready documents" do
      expect(KnowledgeDocument.ready).to contain_exactly(ready_doc, other_doc)
    end

    it ".pending returns only pending documents" do
      expect(KnowledgeDocument.pending).to contain_exactly(pending_doc)
    end
  end

  it "destroys chunks when destroyed" do
    doc = create(:knowledge_document)
    create(:knowledge_chunk, knowledge_document: doc)
    expect { doc.destroy }.to change(KnowledgeChunk, :count).by(-1)
  end
end
