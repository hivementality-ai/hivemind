# frozen_string_literal: true

require "rails_helper"

RSpec.describe TaskAttachment, type: :model do
  describe "associations" do
    it { should belong_to(:task) }
  end

  describe "validations" do
    subject { build(:task_attachment) }

    it { should validate_presence_of(:title) }
    it { should validate_presence_of(:url) }

    it "accepts a valid https URL" do
      attachment = build(:task_attachment, url: "https://example.com/file.pdf")
      expect(attachment).to be_valid
    end

    it "accepts a valid http URL" do
      attachment = build(:task_attachment, url: "http://example.com/file.pdf")
      expect(attachment).to be_valid
    end

    it "rejects a non-URL string" do
      attachment = build(:task_attachment, url: "not a url")
      expect(attachment).not_to be_valid
      expect(attachment.errors[:url]).to be_present
    end

    it "rejects a blank title" do
      attachment = build(:task_attachment, title: "")
      expect(attachment).not_to be_valid
    end
  end

  describe "#kind" do
    it "returns 'pdf' for application/pdf" do
      attachment = build(:task_attachment, content_type: "application/pdf")
      expect(attachment.kind).to eq("pdf")
    end

    it "returns 'image' for image/* content types" do
      attachment = build(:task_attachment, content_type: "image/png")
      expect(attachment.kind).to eq("image")
    end

    it "returns 'spreadsheet' for xlsx" do
      attachment = build(:task_attachment, content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      expect(attachment.kind).to eq("spreadsheet")
    end

    it "returns 'document' for text/plain" do
      attachment = build(:task_attachment, content_type: "text/plain")
      expect(attachment.kind).to eq("document")
    end

    it "returns 'link' for unknown content types" do
      attachment = build(:task_attachment, content_type: "application/octet-stream")
      expect(attachment.kind).to eq("link")
    end
  end

  describe "#resolved_content_type" do
    it "returns the stored content_type when present" do
      attachment = build(:task_attachment, content_type: "application/pdf")
      expect(attachment.resolved_content_type).to eq("application/pdf")
    end

    it "infers content type from URL extension when content_type is blank" do
      attachment = build(:task_attachment, content_type: nil, url: "https://example.com/sheet.xlsx")
      expect(attachment.resolved_content_type).to eq("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    end

    it "falls back to application/octet-stream for unknown extensions" do
      attachment = build(:task_attachment, content_type: nil, url: "https://example.com/file.xyz")
      expect(attachment.resolved_content_type).to eq("application/octet-stream")
    end
  end

  describe "Task association" do
    it "is destroyed when the parent task is destroyed" do
      task       = create(:task)
      attachment = create(:task_attachment, task: task)
      task.destroy
      expect(TaskAttachment.where(id: attachment.id)).not_to exist
    end
  end

  describe "scopes" do
    describe ".recent" do
      it "orders by created_at descending" do
        task  = create(:task)
        older = create(:task_attachment, task: task, created_at: 2.hours.ago)
        newer = create(:task_attachment, task: task, created_at: 1.hour.ago)
        expect(task.task_attachments.recent).to eq([ newer, older ])
      end
    end
  end
end
