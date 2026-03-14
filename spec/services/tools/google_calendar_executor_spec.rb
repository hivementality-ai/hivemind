# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::GoogleCalendarExecutor, type: :service do
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
    it "returns failure when calendar scope not granted" do
      VaultEntry.find_by(namespace: namespace, key: "scopes").update!(value: "https://www.googleapis.com/auth/drive")

      response = execute("action" => "list")
      expect(response.success?).to be false
      expect(response.error).to include("Calendar access not authorized")
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
    it "returns formatted event list" do
      gws_output = { "items" => [
        { "summary" => "Team Standup", "start" => { "dateTime" => "2026-03-13T09:00:00Z" }, "end" => { "dateTime" => "2026-03-13T09:30:00Z" } },
        { "summary" => "Lunch", "start" => { "dateTime" => "2026-03-13T12:00:00Z" }, "end" => { "dateTime" => "2026-03-13T13:00:00Z" } }
      ] }.to_json

      allow_any_instance_of(described_class).to receive(:gws).and_return(gws_output)

      response = execute("action" => "list")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("Team Standup")
      expect(response.data[:output]).to include("Lunch")
      expect(response.data[:exit_code]).to eq(0)
    end

    it "returns empty message when no events" do
      gws_output = { "items" => [] }.to_json
      allow_any_instance_of(described_class).to receive(:gws).and_return(gws_output)

      response = execute("action" => "list")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("No upcoming events")
    end

    it "defaults calendar_id to primary" do
      gws_output = { "items" => [] }.to_json
      expect_any_instance_of(described_class).to receive(:gws) do |_instance, *args|
        expect(args).to include("primary")
        gws_output
      end

      execute("action" => "list")
    end
  end

  describe "get action" do
    it "requires an event_id" do
      response = execute("action" => "get", "event_id" => "")
      expect(response.success?).to be false
      expect(response.error).to include("No event_id provided")
    end

    it "returns event details" do
      gws_output = {
        "summary" => "Design Review",
        "status" => "confirmed",
        "start" => { "dateTime" => "2026-03-14T14:00:00Z" },
        "end" => { "dateTime" => "2026-03-14T15:00:00Z" },
        "location" => "Room 42",
        "htmlLink" => "https://calendar.google.com/event?eid=abc"
      }.to_json

      allow_any_instance_of(described_class).to receive(:gws).and_return(gws_output)

      response = execute("action" => "get", "event_id" => "evt123")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("Design Review")
      expect(response.data[:output]).to include("Room 42")
    end
  end

  describe "create action" do
    it "requires summary" do
      response = execute("action" => "create", "summary" => "", "start_time" => "2026-03-14T10:00:00Z", "end_time" => "2026-03-14T11:00:00Z")
      expect(response.success?).to be false
      expect(response.error).to include("No summary provided")
    end

    it "requires start_time" do
      response = execute("action" => "create", "summary" => "Meeting", "start_time" => "", "end_time" => "2026-03-14T11:00:00Z")
      expect(response.success?).to be false
      expect(response.error).to include("No start_time provided")
    end

    it "requires end_time" do
      response = execute("action" => "create", "summary" => "Meeting", "start_time" => "2026-03-14T10:00:00Z", "end_time" => "")
      expect(response.success?).to be false
      expect(response.error).to include("No end_time provided")
    end

    it "creates an event" do
      gws_output = { "summary" => "Planning", "htmlLink" => "https://calendar.google.com/event?eid=xyz" }.to_json
      allow_any_instance_of(described_class).to receive(:gws).and_return(gws_output)

      response = execute(
        "action" => "create",
        "summary" => "Planning",
        "start_time" => "2026-03-14T10:00:00Z",
        "end_time" => "2026-03-14T11:00:00Z"
      )
      expect(response.success?).to be true
      expect(response.data[:output]).to include("Created event")
      expect(response.data[:output]).to include("Planning")
    end
  end

  describe "update action" do
    it "requires event_id" do
      response = execute("action" => "update", "event_id" => "", "updates" => { "summary" => "New Title" })
      expect(response.success?).to be false
      expect(response.error).to include("No event_id provided")
    end

    it "requires updates" do
      response = execute("action" => "update", "event_id" => "evt123")
      expect(response.success?).to be false
      expect(response.error).to include("No updates provided")
    end

    it "updates and returns result" do
      gws_output = { "summary" => "Updated Meeting" }.to_json
      allow_any_instance_of(described_class).to receive(:gws).and_return(gws_output)

      response = execute("action" => "update", "event_id" => "evt123", "updates" => { "summary" => "Updated Meeting" })
      expect(response.success?).to be true
      expect(response.data[:output]).to include("Updated event")
    end
  end

  describe "delete action" do
    it "requires event_id" do
      response = execute("action" => "delete", "event_id" => "")
      expect(response.success?).to be false
      expect(response.error).to include("No event_id provided")
    end

    it "deletes and confirms" do
      allow_any_instance_of(described_class).to receive(:gws).and_return("")

      response = execute("action" => "delete", "event_id" => "evt123")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("Deleted event")
    end
  end

  describe "calendars action" do
    it "returns list of calendars" do
      gws_output = { "items" => [
        { "summary" => "Work", "id" => "work@group.calendar.google.com" },
        { "summary" => "Personal", "id" => "user@gmail.com" }
      ] }.to_json

      allow_any_instance_of(described_class).to receive(:gws).and_return(gws_output)

      response = execute("action" => "calendars")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("Work")
      expect(response.data[:output]).to include("Personal")
    end
  end

  describe "error handling" do
    it "wraps unexpected errors" do
      allow_any_instance_of(described_class).to receive(:gws).and_raise(StandardError, "timeout")

      response = execute("action" => "list")
      expect(response.success?).to be false
      expect(response.error).to include("Google Calendar error")
    end
  end
end
