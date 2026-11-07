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

  describe "backend selection" do
    let(:imap_result) { ServiceResponse.success(data: { output: "from imap", exit_code: 0 }) }

    def add_app_password
      create(:vault_entry, namespace: "google", key: "gmail_address", value: "me@gmail.com")
      create(:vault_entry, namespace: "google", key: "gmail_app_password", value: "app password")
    end

    before { allow_any_instance_of(Tools::Gmail::ImapBackend).to receive(:call).and_return(imap_result) }

    it "uses the Google connection when it grants Gmail, even with an app password saved" do
      add_app_password
      allow_any_instance_of(described_class).to receive(:gws).and_return({ "messages" => [] }.to_json)

      response = execute("action" => "list")

      expect(response.data[:output]).to include("No messages found")
    end

    it "falls back to the app password when Google is not connected" do
      VaultEntry.where(namespace: namespace).destroy_all
      add_app_password

      expect(execute("action" => "list").data[:output]).to eq("from imap")
    end

    it "falls back to the app password when Google tokens were removed but the scope record remains" do
      VaultEntry.where(namespace: namespace, key: %w[access_token refresh_token]).destroy_all
      add_app_password

      expect(execute("action" => "list").data[:output]).to eq("from imap")
    end

    it "falls back to the app password when Google lacks the Gmail scope" do
      VaultEntry.find_by(namespace: namespace, key: "scopes").update!(value: "https://www.googleapis.com/auth/drive")
      add_app_password

      expect(execute("action" => "list").data[:output]).to eq("from imap")
    end

    it "tells the user how to connect Gmail when neither is set up" do
      VaultEntry.where(namespace: namespace).destroy_all

      response = execute("action" => "list")

      expect(response.success?).to be false
      expect(response.error).to include("Gmail access not authorized")
      expect(response.error).to include("Google Workspace")
      expect(response.error).to include("app password")
    end

    it "accepts uid in place of message_id on the Google backend" do
      allow_any_instance_of(described_class).to receive(:gws).and_return({ "id" => "m1", "payload" => { "headers" => [] } }.to_json)

      expect(execute("action" => "get", "uid" => "m1").success?).to be true
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
        args_str = args.join(" ")
        if call_count == 1
          list_output
        elsif args_str.include?("msg001")
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
        "labelIds" => [ "INBOX", "UNREAD" ],
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
      list_output = { "messages" => [ { "id" => "msg001" } ] }.to_json
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
      allow_any_instance_of(described_class).to receive(:gws).and_return("")

      response = execute("action" => "send", "to" => "bob@example.com", "subject" => "Hello", "body" => "Hi Bob!")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("Sent message to bob@example.com")
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

  describe "inbox action (carried over from the retired gmail tool)" do
    it "lists the INBOX label with the requested limit" do
      seen = []
      allow_any_instance_of(described_class).to receive(:gws) do |_instance, *args|
        seen << args
        { "messages" => [] }.to_json
      end

      response = execute("action" => "inbox", "limit" => 5)

      expect(response.success?).to be true
      params = JSON.parse(seen.first[seen.first.index("--params") + 1])
      expect(params).to include("labelIds" => "INBOX", "maxResults" => 5)
    end

    it "accepts read as an alias for inbox" do
      seen = []
      allow_any_instance_of(described_class).to receive(:gws) do |_instance, *args|
        seen << args
        { "messages" => [] }.to_json
      end

      execute("action" => "read")

      params = JSON.parse(seen.first[seen.first.index("--params") + 1])
      expect(params["labelIds"]).to eq("INBOX")
    end

    it "does not restrict a plain list to the inbox" do
      seen = []
      allow_any_instance_of(described_class).to receive(:gws) do |_instance, *args|
        seen << args
        { "messages" => [] }.to_json
      end

      execute("action" => "list")

      params = JSON.parse(seen.first[seen.first.index("--params") + 1])
      expect(params).not_to have_key("labelIds")
    end
  end

  describe "reply action (carried over from the retired gmail tool)" do
    let(:original) do
      {
        "id" => "msg001",
        "threadId" => "thread9",
        "payload" => { "headers" => [
          { "name" => "From", "value" => "alice@example.com" },
          { "name" => "Subject", "value" => "Project update" },
          { "name" => "Message-ID", "value" => "<abc@mail.example.com>" }
        ] }
      }
    end

    it "requires message_id and body" do
      response = execute("action" => "reply", "message_id" => "msg001", "body" => "")
      expect(response.success?).to be false
      expect(response.error).to include("message_id and body required")
    end

    it "fails when the original message cannot be found" do
      allow_any_instance_of(described_class).to receive(:gws).and_return(ServiceResponse.failure(error: "gws: 404"))

      response = execute("action" => "reply", "message_id" => "nope", "body" => "Thanks")
      expect(response.success?).to be false
      expect(response.error).to include("Original email not found")
    end

    it "sends on the original thread to the sender with a Re: subject and reply headers" do
      calls = []
      allow_any_instance_of(described_class).to receive(:gws) do |_instance, *args|
        calls << args
        args.include?("get") ? original.to_json : "{}"
      end

      response = execute("action" => "reply", "message_id" => "msg001", "body" => "Thanks!")

      expect(response.success?).to be true
      expect(response.data[:output]).to include("Reply sent to alice@example.com: Re: Project update")
      send_call = calls.find { |c| c.include?("send") }
      payload = JSON.parse(send_call[send_call.index("--json") + 1])
      expect(payload["threadId"]).to eq("thread9")
      raw = Base64.urlsafe_decode64(payload["raw"])
      expect(raw).to include("To: alice@example.com")
      expect(raw).to include("Subject: Re: Project update")
      expect(raw).to include("In-Reply-To: <abc@mail.example.com>")
      expect(raw).to include("References: <abc@mail.example.com>")
    end

    it "prefers Reply-To and does not double the Re: prefix" do
      original["payload"]["headers"] << { "name" => "Reply-To", "value" => "team@example.com" }
      original["payload"]["headers"].find { |h| h["name"] == "Subject" }["value"] = "Re: Project update"
      calls = []
      allow_any_instance_of(described_class).to receive(:gws) do |_instance, *args|
        calls << args
        args.include?("get") ? original.to_json : "{}"
      end

      response = execute("action" => "reply", "message_id" => "msg001", "body" => "Thanks!")

      expect(response.data[:output]).to include("Reply sent to team@example.com: Re: Project update")
      expect(response.data[:output]).not_to include("Re: Re:")
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
