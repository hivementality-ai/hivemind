# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::GoogleDriveExecutor, type: :service do
  let(:agent) { create(:agent) }
  let(:namespace) { "google_workspace" }

  def execute(input)
    described_class.new(agent: agent, input: input).call
  end

  before do
    create(:vault_entry, namespace: namespace, key: "access_token", value: "ya29.test-token")
    create(:vault_entry, namespace: namespace, key: "refresh_token", value: "1//test-refresh")
    create(:vault_entry, namespace: namespace, key: "expires_at", value: 1.hour.from_now.iso8601)
    create(:vault_entry, namespace: namespace, key: "scopes", value: "https://www.googleapis.com/auth/drive https://www.googleapis.com/auth/calendar")
  end

  describe "scope validation" do
    it "returns failure when drive scope not granted" do
      VaultEntry.find_by(namespace: namespace, key: "scopes").update!(value: "https://www.googleapis.com/auth/calendar")

      response = execute("action" => "list")
      expect(response.success?).to be false
      expect(response.error).to include("Drive access not authorized")
    end
  end

  describe "unknown action" do
    it "returns failure with supported actions" do
      response = execute("action" => "nope")
      expect(response.success?).to be false
      expect(response.error).to include("Unknown action")
      expect(response.error).to include("list")
    end
  end

  describe "list action" do
    it "returns formatted file list" do
      gws_output = { "files" => [
        { "id" => "abc123", "name" => "Report.docx", "mimeType" => "application/vnd.google-apps.document" },
        { "id" => "def456", "name" => "Photos", "mimeType" => "application/vnd.google-apps.folder" }
      ] }.to_json

      allow_any_instance_of(described_class).to receive(:gws).and_return(gws_output)

      response = execute("action" => "list")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("Report.docx")
      expect(response.data[:output]).to include("Photos")
      expect(response.data[:exit_code]).to eq(0)
    end

    it "returns empty message when no files" do
      gws_output = { "files" => [] }.to_json
      allow_any_instance_of(described_class).to receive(:gws).and_return(gws_output)

      response = execute("action" => "list")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("No files found")
    end
  end

  describe "search action" do
    it "requires a query" do
      response = execute("action" => "search", "query" => "")
      expect(response.success?).to be false
      expect(response.error).to include("No query provided")
    end

    it "returns matching files" do
      gws_output = { "files" => [
        { "id" => "abc123", "name" => "Q3 Report.pdf", "mimeType" => "application/pdf" }
      ] }.to_json

      allow_any_instance_of(described_class).to receive(:gws).and_return(gws_output)

      response = execute("action" => "search", "query" => "name contains 'Q3'")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("Q3 Report.pdf")
    end
  end

  describe "get action" do
    it "requires a file_id" do
      response = execute("action" => "get", "file_id" => "")
      expect(response.success?).to be false
      expect(response.error).to include("No file_id provided")
    end

    it "returns file metadata" do
      gws_output = {
        "id" => "abc123",
        "name" => "Budget.xlsx",
        "mimeType" => "application/vnd.google-apps.spreadsheet",
        "size" => "1024",
        "modifiedTime" => "2026-03-10T12:00:00Z"
      }.to_json

      allow_any_instance_of(described_class).to receive(:gws).and_return(gws_output)

      response = execute("action" => "get", "file_id" => "abc123")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("Budget.xlsx")
      expect(response.data[:output]).to include("1024 bytes")
    end
  end

  describe "create action" do
    it "requires a name" do
      response = execute("action" => "create", "name" => "")
      expect(response.success?).to be false
      expect(response.error).to include("No name provided")
    end

    it "creates a file and returns result" do
      gws_output = { "id" => "new123", "name" => "Notes.txt" }.to_json
      allow_any_instance_of(described_class).to receive(:gws).and_return(gws_output)

      response = execute("action" => "create", "name" => "Notes.txt")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("Created file")
      expect(response.data[:output]).to include("new123")
    end
  end

  describe "upload action" do
    it "requires a local_path" do
      response = execute("action" => "upload", "local_path" => "")
      expect(response.success?).to be false
      expect(response.error).to include("No local_path provided")
    end

    it "uploads and returns result" do
      gws_output = { "id" => "up789", "name" => "data.csv" }.to_json
      allow_any_instance_of(described_class).to receive(:gws).and_return(gws_output)

      response = execute("action" => "upload", "local_path" => "/workspace/data.csv")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("Uploaded")
      expect(response.data[:output]).to include("up789")
    end
  end

  describe "download action" do
    it "requires a file_id" do
      response = execute("action" => "download", "file_id" => "")
      expect(response.success?).to be false
      expect(response.error).to include("No file_id provided")
    end

    it "downloads file content" do
      allow_any_instance_of(described_class).to receive(:gws).and_return("file content here")

      response = execute("action" => "download", "file_id" => "abc123")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("file content here")
    end
  end

  describe "error handling" do
    it "wraps unexpected errors" do
      allow_any_instance_of(described_class).to receive(:gws).and_raise(StandardError, "connection reset")

      response = execute("action" => "list")
      expect(response.success?).to be false
      expect(response.error).to include("Google Drive error")
      expect(response.error).to include("connection reset")
    end
  end
end
