# frozen_string_literal: true

require "open3"
require "json"
require "timeout"

module Tools
  class GoogleCalendarExecutor < BaseExecutor
    TIMEOUT = 30
    REQUIRED_SCOPE = "https://www.googleapis.com/auth/calendar"

    def call
      return scope_error unless scope_granted?

      action = input["action"].to_s.strip

      case action
      when "list"
        list_events
      when "get"
        get_event
      when "create"
        create_event
      when "update"
        update_event
      when "delete"
        delete_event
      when "calendars"
        list_calendars
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Supported: list, get, create, update, delete, calendars")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Google Calendar error: #{e.message}")
    end

    private

    def list_events
      calendar_id = resolve_calendar_id
      params = input["params"] || {}
      params["timeMin"] ||= Time.current.iso8601
      params["maxResults"] ||= 20
      params["singleEvents"] = true
      params["orderBy"] = "startTime"

      result = gws("calendar", "events", "list", "--params", params.merge("calendarId" => calendar_id).to_json)
      return result if result.is_a?(ServiceResponse) && !result.success?

      events = parse_events(result)
      if events.any?
        output = events.map { |e| format_event(e) }.join("\n\n")
        ServiceResponse.success(data: { output: "Upcoming events:\n#{output}", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "No upcoming events.", exit_code: 0 })
      end
    end

    def get_event
      calendar_id = resolve_calendar_id
      event_id = input["event_id"].to_s.strip
      return ServiceResponse.failure(error: "No event_id provided") if event_id.empty?

      result = gws("calendar", "events", "get", "--params", { "calendarId" => calendar_id, "eventId" => event_id }.to_json)
      return result if result.is_a?(ServiceResponse) && !result.success?

      data = JSON.parse(result) rescue result
      output = data.is_a?(Hash) ? format_event_detail(data) : result

      ServiceResponse.success(data: { output: output, exit_code: 0 })
    end

    def create_event
      calendar_id = resolve_calendar_id
      summary = input["summary"].to_s.strip
      return ServiceResponse.failure(error: "No summary provided") if summary.empty?

      event = { "summary" => summary }
      event["description"] = input["description"] if input["description"].present?
      event["location"] = input["location"] if input["location"].present?

      start_time = input["start_time"].to_s.strip
      end_time = input["end_time"].to_s.strip
      return ServiceResponse.failure(error: "No start_time provided") if start_time.empty?
      return ServiceResponse.failure(error: "No end_time provided") if end_time.empty?

      timezone = input["timezone"] || "UTC"
      event["start"] = { "dateTime" => start_time, "timeZone" => timezone }
      event["end"] = { "dateTime" => end_time, "timeZone" => timezone }

      if input["attendees"].present?
        event["attendees"] = Array(input["attendees"]).map { |email| { "email" => email } }
      end

      result = gws("calendar", "events", "insert", "--params", { "calendarId" => calendar_id }.to_json, "--json", event.to_json)
      return result if result.is_a?(ServiceResponse) && !result.success?

      data = JSON.parse(result) rescue result
      if data.is_a?(Hash)
        ServiceResponse.success(data: { output: "Created event: #{data["summary"]} (#{data["htmlLink"]})", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "Created event: #{result}", exit_code: 0 })
      end
    end

    def update_event
      calendar_id = resolve_calendar_id
      event_id = input["event_id"].to_s.strip
      return ServiceResponse.failure(error: "No event_id provided") if event_id.empty?

      updates = input["updates"] || {}
      return ServiceResponse.failure(error: "No updates provided") if updates.empty?

      result = gws("calendar", "events", "patch", "--params", { "calendarId" => calendar_id, "eventId" => event_id }.to_json, "--json", updates.to_json)
      return result if result.is_a?(ServiceResponse) && !result.success?

      data = JSON.parse(result) rescue result
      if data.is_a?(Hash)
        ServiceResponse.success(data: { output: "Updated event: #{data["summary"]}", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "Updated event.", exit_code: 0 })
      end
    end

    def delete_event
      calendar_id = resolve_calendar_id
      event_id = input["event_id"].to_s.strip
      return ServiceResponse.failure(error: "No event_id provided") if event_id.empty?

      result = gws("calendar", "events", "delete", "--params", { "calendarId" => calendar_id, "eventId" => event_id }.to_json)
      return result if result.is_a?(ServiceResponse) && !result.success?

      ServiceResponse.success(data: { output: "Deleted event #{event_id}.", exit_code: 0 })
    end

    def list_calendars
      result = gws("calendar", "calendarList", "list", "--params", {}.to_json)
      return result if result.is_a?(ServiceResponse) && !result.success?

      data = JSON.parse(result) rescue {}
      calendars = data["items"] || []

      if calendars.any?
        output = calendars.map { |c| "- #{c["summary"]} (#{c["id"]})" }.join("\n")
        ServiceResponse.success(data: { output: "Calendars:\n#{output}", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "No calendars found.", exit_code: 0 })
      end
    end

    # ─── Helpers ───────────────────────────────────────────────────

    def gws(*args)
      GoogleWorkspace::CredentialBridge.call do |env|
        stdout, stderr, status = Timeout.timeout(TIMEOUT) do
          Open3.capture3(env, "gws", *args)
        end

        unless status.success?
          error_msg = stderr.to_s.strip
          error_msg = stdout.to_s.strip if error_msg.blank?
          error_msg = "exit code #{status.exitstatus}" if error_msg.blank?
          return ServiceResponse.failure(error: "gws: #{error_msg.truncate(500)}")
        end

        stdout.to_s.strip
      end
    end

    def resolve_calendar_id
      input["calendar_id"].to_s.strip.presence || "primary"
    end

    def scope_granted?
      scopes = GoogleWorkspace::CredentialBridge.granted_scopes.to_s
      scopes.include?(REQUIRED_SCOPE)
    end

    def scope_error
      ServiceResponse.failure(
        error: "Google Calendar access not authorized. Please grant Calendar permissions at /integrations."
      )
    end

    def parse_events(raw)
      data = JSON.parse(raw) rescue {}
      data["items"] || []
    end

    def format_event(event)
      start_str = event.dig("start", "dateTime") || event.dig("start", "date") || "?"
      end_str = event.dig("end", "dateTime") || event.dig("end", "date") || "?"
      "- #{event["summary"] || "(No title)"}\n  #{start_str} → #{end_str}"
    end

    def format_event_detail(event)
      lines = []
      lines << "Summary: #{event["summary"]}"
      lines << "Status: #{event["status"]}" if event["status"]
      lines << "Start: #{event.dig("start", "dateTime") || event.dig("start", "date")}"
      lines << "End: #{event.dig("end", "dateTime") || event.dig("end", "date")}"
      lines << "Location: #{event["location"]}" if event["location"]
      lines << "Description: #{event["description"]}" if event["description"]
      lines << "Link: #{event["htmlLink"]}" if event["htmlLink"]
      if event["attendees"]
        attendees = event["attendees"].map { |a| "  - #{a["email"]} (#{a["responseStatus"]})" }.join("\n")
        lines << "Attendees:\n#{attendees}"
      end
      lines.join("\n")
    end
  end
end
