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

  describe "page numbers" do
    let(:pdf_text) do
      "\n--- Page 1 ---\none two three four five\n\n--- Page 2 ---\nsix seven eight nine ten\n\n--- Page 3 ---\neleven twelve thirteen fourteen fifteen\n"
    end

    before do
      stub_const("#{described_class}::CHUNK_WORDS", 6)
      stub_const("#{described_class}::CHUNK_OVERLAP", 2)
      allow(Tools::PdfReadExecutor).to receive(:new).and_return(
        instance_double(Tools::PdfReadExecutor, call: ServiceResponse.success(data: { output: pdf_text, exit_code: 0 }))
      )
    end

    it "records the pages each PDF chunk came from" do
      doc = create(:knowledge_document, agent: agent, source_type: "pdf", source_url: "/workspace/a.pdf", status: "pending")

      described_class.perform_now(doc.id)

      chunks = doc.reload.chunks.order(:position)
      expect(chunks.map { |c| [ c.page_start, c.page_end ] }).to eq([ [ 1, 2 ], [ 1, 2 ], [ 2, 3 ], [ 3, 3 ] ])
      expect(chunks.first.content).to eq("one two three four five six")
      expect(chunks.map(&:content).join).not_to include("Page")
    end

    it "leaves pages nil for text documents" do
      doc = write_text_doc("alpha beta gamma delta epsilon zeta eta theta")

      described_class.perform_now(doc.id)

      expect(doc.reload.chunks.pluck(:page_start, :page_end).uniq).to eq([ [ nil, nil ] ])
    end
  end
end
