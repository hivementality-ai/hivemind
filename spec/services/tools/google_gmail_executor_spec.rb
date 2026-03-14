# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::GoogleGmailExecutor, type: :service do
  let(:agent) { create(:agent) }
  let(:namespace) { "google_workspace" }

  def execute(input)
    described_class.new(agent: agent, input: input).call
  end

  before do
    create(:vault_entry, namespace: namespace, key: "access_token", value: "ya29.test-token")
    create(:vault_entry, namespace: namespace, key: "refresh_token", value: "1//test-refresh")
    create(:vault_entry, namespace: namespace, key: "expires_at", value: 1.hour.from_now.iso8601)
    create(:vault_entry, namespace: namespace, key: "scopes", value: "https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/drive")
  end

  describe "scope validation" do
    it "returns failure when gmail scope not granted" do
      VaultEntry.find_by(namespace: namespace, key: "scopes").update!(value: "https://www.googleapis.com/auth/drive")

      response = execute("action" => "list")
      expect(response.success?).to be false
      expect(response.error).to include("Gmail access not authorized")
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
    it "fetches and displays message summaries" do
      list_output = { "messages" => [
        { "id" => "msg001", "threadId" => "t001" },
        { "id" => "msg002", "threadId" => "t002" }
      ] }.to_json

      summary1 = {
        "id" => "msg001",
        "payload" => { "headers" => [
          { "name" => "From", "value" => "alice@example.com" },
          { "name" => "Subject", "value" => "Hello" },
          { "name" => "Date", "value" => "Thu, 12 Mar 2026 10:00:00 -0000" }
        ] }
      }

      summary2 = {
        "id" => "msg002",
        "payload" => { "headers" => [
          { "name" => "From", "value" => "bob@example.com" },
          { "name" => "Subject", "value" => "Meeting notes" },
          { "name" => "Date", "value" => "Thu, 12 Mar 2026 11:00:00 -0000" }
        ] }
      }

      call_count = 0
      allow_any_instance_of(described_class).to receive(:gws) do |_instance, *args|
        call_count += 1
        if call_count == 1
          list_output
        elsif args.include?("msg001")
          summary1.to_json
        else
          summary2.to_json
        end
      end

      response = execute("action" => "list")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("alice@example.com")
      expect(response.data[:output]).to include("bob@example.com")
      expect(response.data[:output]).to include("Hello")
    end

    it "returns empty message when no messages" do
      gws_output = { "messages" => nil }.to_json
      allow_any_instance_of(described_class).to receive(:gws).and_return(gws_output)

      response = execute("action" => "list")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("No messages found")
    end
  end

  describe "get action" do
    it "requires message_id" do
      response = execute("action" => "get", "message_id" => "")
      expect(response.success?).to be false
      expect(response.error).to include("No message_id provided")
    end

    it "returns formatted message" do
      gws_output = {
        "id" => "msg001",
        "labelIds" => ["INBOX", "UNREAD"],
        "payload" => {
          "headers" => [
            { "name" => "From", "value" => "alice@example.com" },
            { "name" => "To", "value" => "me@example.com" },
            { "name" => "Subject", "value" => "Project update" },
            { "name" => "Date", "value" => "Thu, 12 Mar 2026 10:00:00 -0000" }
          ],
          "body" => { "data" => Base64.urlsafe_encode64("Hello, here is the update.") }
        }
      }.to_json

      allow_any_instance_of(described_class).to receive(:gws).and_return(gws_output)

      response = execute("action" => "get", "message_id" => "msg001")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("alice@example.com")
      expect(response.data[:output]).to include("Project update")
      expect(response.data[:output]).to include("Hello, here is the update.")
    end
  end

  describe "search action" do
    it "requires a query" do
      response = execute("action" => "search", "query" => "")
      expect(response.success?).to be false
      expect(response.error).to include("No query provided")
    end

    it "returns matching messages" do
      list_output = { "messages" => [{ "id" => "msg001" }] }.to_json
      summary = {
        "id" => "msg001",
        "payload" => { "headers" => [
          { "name" => "From", "value" => "support@example.com" },
          { "name" => "Subject", "value" => "Invoice #123" },
          { "name" => "Date", "value" => "Thu, 12 Mar 2026 10:00:00 -0000" }
        ] }
      }

      call_count = 0
      allow_any_instance_of(described_class).to receive(:gws) do |_instance, *args|
        call_count += 1
        call_count == 1 ? list_output : summary.to_json
      end

      response = execute("action" => "search", "query" => "invoice")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("Invoice #123")
    end
  end

  describe "send action" do
    it "requires to address" do
      response = execute("action" => "send", "to" => "", "subject" => "Hi", "body" => "Hello")
      expect(response.success?).to be false
      expect(response.error).to include("No 'to' address provided")
    end

    it "requires subject" do
      response = execute("action" => "send", "to" => "bob@example.com", "subject" => "", "body" => "Hello")
      expect(response.success?).to be false
      expect(response.error).to include("No subject provided")
    end

    it "requires body" do
      response = execute("action" => "send", "to" => "bob@example.com", "subject" => "Hi", "body" => "")
      expect(response.success?).to be false
      expect(response.error).to include("No body provided")
    end

    it "sends a message" do
      gws_output = { "id" => "sent001", "labelIds" => ["SENT"] }.to_json
      allow_any_instance_of(described_class).to receive(:gws).and_return(gws_output)

      response = execute("action" => "send", "to" => "bob@example.com", "subject" => "Hello", "body" => "Hi Bob!")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("Sent message to bob@example.com")
      expect(response.data[:output]).to include("sent001")
    end
  end

  describe "draft action" do
    it "requires to address" do
      response = execute("action" => "draft", "to" => "", "subject" => "Hi", "body" => "Hello")
      expect(response.success?).to be false
      expect(response.error).to include("No 'to' address provided")
    end

    it "creates a draft" do
      gws_output = { "id" => "draft001" }.to_json
      allow_any_instance_of(described_class).to receive(:gws).and_return(gws_output)

      response = execute("action" => "draft", "to" => "bob@example.com", "subject" => "Draft", "body" => "WIP")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("Created draft to bob@example.com")
    end
  end

  describe "error handling" do
    it "wraps unexpected errors" do
      allow_any_instance_of(described_class).to receive(:gws).and_raise(StandardError, "API limit exceeded")

      response = execute("action" => "list")
      expect(response.success?).to be false
      expect(response.error).to include("Google Gmail error")
      expect(response.error).to include("API limit exceeded")
    end
  end
end
