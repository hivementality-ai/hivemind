# frozen_string_literal: true

require "rails_helper"

RSpec.describe KnowledgeIngestionJob, type: :job do
  let(:agent) { create(:agent) }
  let(:embedding) { Array.new(768) { |i| (i % 10) * 0.1 } }

  # Stub the embedding adapter the same way the memory specs do.
  before { allow(Memory::Embedding).to receive(:generate).and_return(embedding) }

  def write_text_doc(text)
    file = Tempfile.new([ "kb", ".txt" ])
    file.write(text)
    file.close
    create(:knowledge_document, agent: agent, source_type: "text", source_url: file.path, status: "pending")
  end

  it "chunks, embeds, and marks the document ready" do
    doc = write_text_doc((1..2000).map { |n| "word#{n}" }.join(" "))

    described_class.perform_now(doc.id)

    doc.reload
    expect(doc.status).to eq("ready")
    expect(doc.chunks.count).to be > 1
    expect(doc.chunks.first.embedding.size).to eq(768)
    expect(doc.chunks.first.embedding.first.to_f).to be_within(1e-5).of(embedding.first)
    expect(doc.chunks.pluck(:position)).to eq((0...doc.chunks.count).to_a)
  end

  it "marks the document failed when no text is extracted" do
    doc = write_text_doc("")

    described_class.perform_now(doc.id)

    doc.reload
    expect(doc.status).to eq("failed")
    expect(doc.error).to be_present
    expect(doc.chunks.count).to eq(0)
  end

  it "re-ingestion replaces prior chunks" do
    doc = write_text_doc("hello world")
    create(:knowledge_chunk, knowledge_document: doc, agent: agent, content: "stale")

    described_class.perform_now(doc.id)

    expect(doc.reload.chunks.pluck(:content)).not_to include("stale")
  end
end
