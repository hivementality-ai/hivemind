# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatAttachment, type: :model do
  describe "associations" do
    it { should belong_to(:session) }
  end

  describe "validations" do
    it { should validate_presence_of(:content_type) }
  end

  describe "#image?" do
    it "returns true for image types" do
      %w[image/jpeg image/png image/gif image/webp].each do |type|
        attachment = build(:chat_attachment, content_type: type)
        expect(attachment.image?).to be true
      end
    end

    it "returns false for non-image types" do
      attachment = build(:chat_attachment, content_type: "text/plain")
      expect(attachment.image?).to be false
    end
  end

  describe "#document?" do
    it "returns true for non-image types" do
      attachment = build(:chat_attachment, content_type: "application/pdf")
      expect(attachment.document?).to be true
    end

    it "returns false for image types" do
      attachment = build(:chat_attachment, content_type: "image/png")
      expect(attachment.document?).to be false
    end
  end

  describe "#text_extractable?" do
    it "returns true for text-based types" do
      %w[text/plain text/markdown text/csv application/json].each do |type|
        attachment = build(:chat_attachment, content_type: type)
        expect(attachment.text_extractable?).to be true
      end
    end

    it "returns false for binary types" do
      attachment = build(:chat_attachment, content_type: "application/pdf")
      expect(attachment.text_extractable?).to be false
    end
  end

  describe "#media_type" do
    it "returns the content_type" do
      attachment = build(:chat_attachment, content_type: "image/jpeg")
      expect(attachment.media_type).to eq("image/jpeg")
    end
  end

  describe "#extract_text" do
    let(:session) { create(:session) }
    let(:attachment) { create(:chat_attachment, session: session, content_type: "text/plain", filename: "test.txt") }

    it "returns nil when no file attached" do
      expect(attachment.extract_text).to be_nil
    end

    context "with attached text file" do
      before do
        attachment.file.attach(io: StringIO.new("Hello world"), filename: "test.txt", content_type: "text/plain")
      end

      it "extracts text content" do
        expect(attachment.extract_text).to eq("Hello world")
      end
    end

    context "with binary content_type and attached file" do
      let(:attachment) { create(:chat_attachment, session: session, content_type: "application/msword", filename: "doc.docx", byte_size: 500) }

      before do
        attachment.file.attach(io: StringIO.new("binary"), filename: "doc.docx", content_type: "application/msword")
      end

      it "returns file info string" do
        expect(attachment.extract_text).to include("[Uploaded file: doc.docx")
      end
    end
  end

  describe "#to_base64" do
    let(:session) { create(:session) }
    let(:attachment) { create(:chat_attachment, session: session) }

    it "returns nil when no file attached" do
      expect(attachment.to_base64).to be_nil
    end

    context "with attached file" do
      before do
        attachment.file.attach(io: StringIO.new("test data"), filename: "test.png", content_type: "image/png")
      end

      it "returns base64 encoded content" do
        expect(attachment.to_base64).to eq(Base64.strict_encode64("test data"))
      end
    end
  end
end
