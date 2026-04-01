# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::ChatAttachmentsExecutor do
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent) }

  def build_executor(input)
    described_class.new(input: input, config: { session: session }, agent: agent)
  end

  describe "#call" do
    context "with no session" do
      it "returns failure" do
        executor = described_class.new(input: { "action" => "list" }, config: {}, agent: agent)
        result = executor.call
        expect(result.success?).to be false
        expect(result.error).to include("No session context")
      end
    end

    context "with invalid action" do
      it "returns failure" do
        result = build_executor("action" => "destroy").call
        expect(result.success?).to be false
        expect(result.error).to include("Unknown action")
      end
    end

    context "list action" do
      it "returns empty message when no attachments" do
        result = build_executor("action" => "list").call
        expect(result.success?).to be true
        expect(result.data[:output]).to include("No attachments")
      end

      it "lists 1:1 chat attachments" do
        attachment = session.chat_attachments.create!(
          content_type: "image/png",
          filename: "screenshot.png",
          byte_size: 2048
        )
        attachment.file.attach(
          io: StringIO.new("fake image data"),
          filename: "screenshot.png",
          content_type: "image/png"
        )

        result = build_executor("action" => "list").call
        expect(result.success?).to be true
        expect(result.data[:output]).to include("screenshot.png")
        expect(result.data[:output]).to include("image")
        expect(result.data[:output]).to include("1 attachment(s)")
      end

      it "defaults to list when no action specified" do
        result = build_executor({}).call
        expect(result.success?).to be true
        expect(result.data[:output]).to include("No attachments")
      end
    end

    context "download action" do
      it "returns failure when no attachment_id provided" do
        result = build_executor("action" => "download").call
        expect(result.success?).to be false
        expect(result.error).to include("No attachment_id")
      end

      it "returns failure for nonexistent attachment" do
        result = build_executor("action" => "download", "attachment_id" => 99999).call
        expect(result.success?).to be false
        expect(result.error).to include("not found")
      end

      it "downloads a 1:1 chat attachment to workspace" do
        attachment = session.chat_attachments.create!(
          content_type: "text/plain",
          filename: "notes.txt",
          byte_size: 11
        )
        attachment.file.attach(
          io: StringIO.new("hello world"),
          filename: "notes.txt",
          content_type: "text/plain"
        )

        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:exist?).and_return(false)
        allow(File).to receive(:binwrite)

        result = build_executor("action" => "download", "attachment_id" => attachment.id).call
        expect(result.success?).to be true
        expect(result.data[:output]).to include("Downloaded notes.txt")
        expect(result.data[:output]).to include("file_read")
      end
    end
  end
end
