# frozen_string_literal: true

require "open3"
require "json"
require "timeout"
require "base64"

module Tools
  class GoogleGmailExecutor < BaseExecutor
    TIMEOUT = 30
    MAX_OUTPUT = 50_000
    REQUIRED_SCOPE = "https://www.googleapis.com/auth/gmail.modify"
    USER_ID = "me"

    def call
      return scope_error unless scope_granted?

      action = input["action"].to_s.strip

      case action
      when "list"
        list_messages
      when "get"
        get_message
      when "search"
        search_messages
      when "send"
        send_message
      when "draft"
        create_draft
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Supported: list, get, search, send, draft")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Google Gmail error: #{e.message}")
    end

    private

    def list_messages
      params = input["params"] || {}
      params["maxResults"] ||= 20

      result = gws("gmail", "users", "messages", "list", "--params", params.merge("userId" => USER_ID).to_json)
      return result if result.is_a?(ServiceResponse) && !result.success?

      data = JSON.parse(result) rescue {}
      messages = data["messages"] || []

      if messages.empty?
        return ServiceResponse.success(data: { output: "No messages found.", exit_code: 0 })
      end

      summaries = messages.first(20).map { |m| fetch_message_summary(m["id"]) }.compact
      output = summaries.map { |s| format_message_summary(s) }.join("\n\n")
      ServiceResponse.success(data: { output: "Messages:\n#{output}", exit_code: 0 })
    end

    def get_message
      message_id = input["message_id"].to_s.strip
      return ServiceResponse.failure(error: "No message_id provided") if message_id.empty?

      result = gws("gmail", "users", "messages", "get", "--params", { "userId" => USER_ID, "id" => message_id }.to_json)
      return result if result.is_a?(ServiceResponse) && !result.success?

      data = JSON.parse(result) rescue result
      output = data.is_a?(Hash) ? format_message_detail(data) : result

      ServiceResponse.success(data: { output: output.to_s.truncate(MAX_OUTPUT), exit_code: 0 })
    end

    def search_messages
      query = input["query"].to_s.strip
      return ServiceResponse.failure(error: "No query provided") if query.empty?

      params = { "q" => query, "maxResults" => input["max_results"] || 20 }
      result = gws("gmail", "users", "messages", "list", "--params", params.merge("userId" => USER_ID).to_json)
      return result if result.is_a?(ServiceResponse) && !result.success?

      data = JSON.parse(result) rescue {}
      messages = data["messages"] || []

      if messages.empty?
        return ServiceResponse.success(data: { output: "No messages matching '#{query}'.", exit_code: 0 })
      end

      summaries = messages.first(20).map { |m| fetch_message_summary(m["id"]) }.compact
      output = summaries.map { |s| format_message_summary(s) }.join("\n\n")
      ServiceResponse.success(data: { output: "Found #{messages.size} message(s) for '#{query}':\n#{output}", exit_code: 0 })
    end

    def send_message
      to = input["to"].to_s.strip
      subject = input["subject"].to_s.strip
      body = input["body"].to_s.strip
      return ServiceResponse.failure(error: "No 'to' address provided") if to.empty?
      return ServiceResponse.failure(error: "No subject provided") if subject.empty?
      return ServiceResponse.failure(error: "No body provided") if body.empty?

      args = [ "gmail", "+send", "--to", to, "--subject", subject, "--body", body ]
      args.push("--cc", input["cc"]) if input["cc"].present?
      args.push("--bcc", input["bcc"]) if input["bcc"].present?

      result = gws(*args)
      return result if result.is_a?(ServiceResponse) && !result.success?

      ServiceResponse.success(data: { output: "Sent message to #{to}.", exit_code: 0 })
    end

    def create_draft
      to = input["to"].to_s.strip
      subject = input["subject"].to_s.strip
      body = input["body"].to_s.strip
      return ServiceResponse.failure(error: "No 'to' address provided") if to.empty?
      return ServiceResponse.failure(error: "No subject provided") if subject.empty?
      return ServiceResponse.failure(error: "No body provided") if body.empty?

      raw = build_raw_message(to: to, subject: subject, body: body, cc: input["cc"], bcc: input["bcc"])
      draft_json = { "message" => { "raw" => raw } }

      result = gws("gmail", "users", "drafts", "create", "--params", { "userId" => USER_ID }.to_json, "--json", draft_json.to_json)
      return result if result.is_a?(ServiceResponse) && !result.success?

      data = JSON.parse(result) rescue result
      if data.is_a?(Hash)
        ServiceResponse.success(data: { output: "Created draft to #{to} (ID: #{data["id"]})", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "Created draft to #{to}.", exit_code: 0 })
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

    def scope_granted?
      scopes = GoogleWorkspace::CredentialBridge.granted_scopes.to_s
      scopes.include?(REQUIRED_SCOPE)
    end

    def scope_error
      ServiceResponse.failure(
        error: "Gmail access not authorized. Please grant Gmail permissions at /integrations."
      )
    end

    def fetch_message_summary(message_id)
      result = gws("gmail", "users", "messages", "get", "--params", { "userId" => USER_ID, "id" => message_id, "format" => "metadata", "metadataHeaders" => "From,To,Subject,Date" }.to_json)
      return nil if result.is_a?(ServiceResponse) && !result.success?

      JSON.parse(result) rescue nil
    end

    def format_message_summary(msg)
      headers = (msg.dig("payload", "headers") || []).each_with_object({}) do |h, map|
        map[h["name"]] = h["value"]
      end

      [
        "ID: #{msg["id"]}",
        "From: #{headers["From"]}",
        "Subject: #{headers["Subject"] || "(No subject)"}",
        "Date: #{headers["Date"]}"
      ].join("\n")
    end

    def format_message_detail(msg)
      headers = (msg.dig("payload", "headers") || []).each_with_object({}) do |h, map|
        map[h["name"]] = h["value"]
      end

      body = extract_body(msg["payload"])

      lines = []
      lines << "From: #{headers["From"]}"
      lines << "To: #{headers["To"]}"
      lines << "Cc: #{headers["Cc"]}" if headers["Cc"]
      lines << "Subject: #{headers["Subject"] || "(No subject)"}"
      lines << "Date: #{headers["Date"]}"
      lines << "Labels: #{msg["labelIds"]&.join(", ")}" if msg["labelIds"]
      lines << ""
      lines << body
      lines.join("\n")
    end

    def extract_body(payload)
      return "" unless payload

      # Direct body data
      if payload.dig("body", "data")
        return Base64.urlsafe_decode64(payload["body"]["data"]).force_encoding("UTF-8")
      end

      # Look through parts for text/plain
      parts = payload["parts"] || []
      text_part = parts.find { |p| p["mimeType"] == "text/plain" }
      if text_part&.dig("body", "data")
        return Base64.urlsafe_decode64(text_part["body"]["data"]).force_encoding("UTF-8")
      end

      # Fall back to text/html
      html_part = parts.find { |p| p["mimeType"] == "text/html" }
      if html_part&.dig("body", "data")
        return Base64.urlsafe_decode64(html_part["body"]["data"]).force_encoding("UTF-8")
      end

      "(No body content)"
    end

    def build_raw_message(to:, subject:, body:, cc: nil, bcc: nil)
      lines = []
      lines << "To: #{to}"
      lines << "Cc: #{cc}" if cc.present?
      lines << "Bcc: #{bcc}" if bcc.present?
      lines << "Subject: #{subject}"
      lines << "Content-Type: text/plain; charset=UTF-8"
      lines << ""
      lines << body

      Base64.urlsafe_encode64(lines.join("\r\n"))
    end
  end
end
