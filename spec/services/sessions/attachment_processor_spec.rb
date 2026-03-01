# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sessions::AttachmentProcessor do
  let(:session) { create(:session) }

  describe ".call" do
    context "with no attachments" do
      subject(:result) { described_class.call(attachment_ids: [], user_message: "Hello") }

      it "returns success with empty collections" do
        expect(result.success?).to be true
        expect(result.data[:images]).to be_empty
        expect(result.data[:documents]).to be_empty
        expect(result.data[:effective_message]).to eq("Hello")
        expect(result.data[:saved_paths]).to be_empty
      end
    end

    context "with nil attachment_ids" do
      subject(:result) { described_class.call(attachment_ids: nil, user_message: "Hello") }

      it "returns success with empty collections" do
        expect(result.success?).to be true
        expect(result.data[:images]).to be_empty
        expect(result.data[:documents]).to be_empty
      end
    end

    context "with image attachments only" do
      let(:image) do
        att = create(:chat_attachment, session: session, content_type: "image/png", filename: "photo.png")
        allow(att).to receive(:image?).and_return(true)
        allow(att).to receive(:document?).and_return(false)
        att
      end

      before { allow(ChatAttachment).to receive(:where).and_return([image]) }

      subject(:result) { described_class.call(attachment_ids: [image.id], user_message: "What is this?") }

      it "classifies images correctly" do
        expect(result.success?).to be true
        expect(result.data[:images]).to eq([image])
        expect(result.data[:documents]).to be_empty
        expect(result.data[:effective_message]).to eq("What is this?")
        expect(result.data[:saved_paths]).to be_empty
      end
    end

    context "with document attachments" do
      let(:doc) do
        att = create(:chat_attachment, session: session, content_type: "application/pdf", filename: "doc.pdf", byte_size: 2048)
        allow(att).to receive(:image?).and_return(false)
        allow(att).to receive(:document?).and_return(true)
        allow(att).to receive(:file).and_return(double(attached?: true, download: "pdf content"))
        att
      end

      before do
        allow(ChatAttachment).to receive(:where).and_return([doc])
        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:binwrite)
      end

      subject(:result) { described_class.call(attachment_ids: [doc.id], user_message: "Read this") }

      it "saves documents and appends file info to message" do
        expect(result.success?).to be true
        expect(result.data[:documents]).to eq([doc])
        expect(result.data[:effective_message]).to include("[Attached Files")
        expect(result.data[:effective_message]).to include("doc.pdf")
        expect(result.data[:effective_message]).to include("Use the file_read tool")
        expect(result.data[:saved_paths]).to be_present
      end

      it "creates workspace directory" do
        result
        expect(FileUtils).to have_received(:mkdir_p).with(%r{/workspace/uploads/})
      end

      it "adds PDF note for PDF files" do
        expect(result.data[:effective_message]).to include("pdf_read tool")
      end
    end

    context "with mixed attachments" do
      let(:image) do
        att = create(:chat_attachment, session: session, content_type: "image/png", filename: "photo.png")
        allow(att).to receive(:image?).and_return(true)
        allow(att).to receive(:document?).and_return(false)
        att
      end

      let(:doc) do
        att = create(:chat_attachment, session: session, content_type: "text/plain", filename: "notes.txt", byte_size: 512)
        allow(att).to receive(:image?).and_return(false)
        allow(att).to receive(:document?).and_return(true)
        allow(att).to receive(:file).and_return(double(attached?: true, download: "text content"))
        att
      end

      before do
        allow(ChatAttachment).to receive(:where).and_return([image, doc])
        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:binwrite)
      end

      subject(:result) { described_class.call(attachment_ids: [image.id, doc.id], user_message: "Check these") }

      it "classifies both types correctly" do
        expect(result.data[:images]).to eq([image])
        expect(result.data[:documents]).to eq([doc])
      end
    end

    context "when file save fails" do
      let(:doc) do
        att = create(:chat_attachment, session: session, content_type: "text/plain", filename: "notes.txt", byte_size: 100)
        allow(att).to receive(:image?).and_return(false)
        allow(att).to receive(:document?).and_return(true)
        allow(att).to receive(:file).and_return(double(attached?: true, download: nil))
        att
      end

      before do
        allow(ChatAttachment).to receive(:where).and_return([doc])
        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:binwrite).and_raise(Errno::ENOSPC, "No space left")
      end

      subject(:result) { described_class.call(attachment_ids: [doc.id], user_message: "Save this") }

      it "handles file save failure gracefully" do
        expect(result.success?).to be true
        expect(result.data[:saved_paths]).to be_empty
        expect(result.data[:effective_message]).to eq("Save this")
      end
    end

    context "file size formatting" do
      let(:small_doc) do
        att = create(:chat_attachment, session: session, content_type: "text/plain", filename: "small.txt", byte_size: 500)
        allow(att).to receive(:image?).and_return(false)
        allow(att).to receive(:document?).and_return(true)
        allow(att).to receive(:file).and_return(double(attached?: true, download: "x"))
        att
      end

      let(:medium_doc) do
        att = create(:chat_attachment, session: session, content_type: "text/plain", filename: "medium.txt", byte_size: 5120)
        allow(att).to receive(:image?).and_return(false)
        allow(att).to receive(:document?).and_return(true)
        allow(att).to receive(:file).and_return(double(attached?: true, download: "x"))
        att
      end

      let(:large_doc) do
        att = create(:chat_attachment, session: session, content_type: "text/plain", filename: "large.txt", byte_size: 2_097_152)
        allow(att).to receive(:image?).and_return(false)
        allow(att).to receive(:document?).and_return(true)
        allow(att).to receive(:file).and_return(double(attached?: true, download: "x"))
        att
      end

      before do
        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:binwrite)
      end

      it "formats bytes for small files" do
        allow(ChatAttachment).to receive(:where).and_return([small_doc])
        result = described_class.call(attachment_ids: [small_doc.id], user_message: "test")
        expect(result.data[:effective_message]).to include("500B")
      end

      it "formats KB for medium files" do
        allow(ChatAttachment).to receive(:where).and_return([medium_doc])
        result = described_class.call(attachment_ids: [medium_doc.id], user_message: "test")
        expect(result.data[:effective_message]).to include("5.0KB")
      end

      it "formats MB for large files" do
        allow(ChatAttachment).to receive(:where).and_return([large_doc])
        result = described_class.call(attachment_ids: [large_doc.id], user_message: "test")
        expect(result.data[:effective_message]).to include("2.0MB")
      end
    end
  end
end
