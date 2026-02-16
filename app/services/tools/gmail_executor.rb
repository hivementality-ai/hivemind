# frozen_string_literal: true

require "net/imap"
require "net/smtp"
require "mail"

module Tools
  class GmailExecutor < BaseExecutor
    # Gmail via IMAP (read) + SMTP (send). No API key needed — uses App Password.
    #
    # Credentials stored in vault:
    #   google/gmail_address  — your@gmail.com
    #   google/gmail_app_password — 16-char app password from Google

    def call
      action = input["action"].to_s.strip

      case action
      when "inbox", "read"
        read_inbox
      when "search"
        search_emails
      when "get"
        get_email
      when "send"
        send_email
      when "reply"
        reply_to_email
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Supported: inbox, search, get, send, reply")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Gmail error: #{e.message}")
    end

    private

    def read_inbox
      limit = (input["limit"] || 10).to_i.clamp(1, 50)
      folder = input["folder"].to_s.strip.presence || "INBOX"

      emails = imap_fetch(folder: folder, limit: limit)
      format_email_list(emails, "#{folder} (#{emails.size} messages)")
    end

    def search_emails
      query = input["query"].to_s.strip
      return ServiceResponse.failure(error: "No query provided") if query.empty?
      limit = (input["limit"] || 10).to_i.clamp(1, 50)

      emails = imap_search(query: query, limit: limit)
      format_email_list(emails, "Search: '#{query}' (#{emails.size} results)")
    end

    def get_email
      uid = input["uid"].to_s.strip
      return ServiceResponse.failure(error: "No uid provided") if uid.empty?

      email = imap_get(uid: uid.to_i)
      return ServiceResponse.failure(error: "Email not found") unless email

      output = []
      output << "From: #{email[:from]}"
      output << "To: #{email[:to]}"
      output << "Subject: #{email[:subject]}"
      output << "Date: #{email[:date]}"
      output << ""
      output << email[:body].to_s.truncate(10_000)

      ServiceResponse.success(data: { output: output.join("\n"), exit_code: 0 })
    end

    def send_email
      to = input["to"].to_s.strip
      subject = input["subject"].to_s.strip
      body = input["body"].to_s.strip

      return ServiceResponse.failure(error: "to, subject, and body required") if [ to, subject, body ].any?(&:empty?)

      smtp_send(to: to, subject: subject, body: body)
      ServiceResponse.success(data: { output: "Email sent to #{to}: #{subject}", exit_code: 0 })
    end

    def reply_to_email
      uid = input["uid"].to_s.strip
      body = input["body"].to_s.strip

      return ServiceResponse.failure(error: "uid and body required") if uid.empty? || body.empty?

      original = imap_get(uid: uid.to_i)
      return ServiceResponse.failure(error: "Original email not found") unless original

      reply_to = original[:from]
      subject = original[:subject]
      subject = "Re: #{subject}" unless subject.start_with?("Re:")

      smtp_send(to: reply_to, subject: subject, body: body, in_reply_to: original[:message_id])
      ServiceResponse.success(data: { output: "Reply sent to #{reply_to}: #{subject}", exit_code: 0 })
    end

    # ─── IMAP ──────────────────────────────────────────────────────

    def imap_fetch(folder:, limit:)
      with_imap do |imap|
        imap.select(folder)
        ids = imap.search([ "ALL" ])
        recent_ids = ids.last(limit)
        return [] if recent_ids.empty?

        fetch_messages(imap, recent_ids).reverse
      end
    end

    def imap_search(query:, limit:)
      with_imap do |imap|
        imap.select("INBOX")

        # IMAP search: try subject, from, and body
        ids = imap.search([ "OR", "SUBJECT", query, "FROM", query ])
        recent_ids = ids.last(limit)
        return [] if recent_ids.empty?

        fetch_messages(imap, recent_ids).reverse
      end
    end

    def imap_get(uid:)
      with_imap do |imap|
        imap.select("INBOX")
        data = imap.uid_fetch(uid, [ "ENVELOPE", "BODY[TEXT]", "BODY[HEADER.FIELDS (MESSAGE-ID)]" ])
        return nil unless data&.first

        msg = data.first
        envelope = msg.attr["ENVELOPE"]
        body_text = msg.attr["BODY[TEXT]"].to_s
        message_id = msg.attr["BODY[HEADER.FIELDS (MESSAGE-ID)]"].to_s.strip

        # Decode body
        decoded_body = begin
          Mail.new(body_text).body.decoded
        rescue StandardError
          body_text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        end

        {
          uid: uid,
          from: format_address(envelope.from),
          to: format_address(envelope.to),
          subject: envelope.subject.to_s,
          date: envelope.date.to_s,
          body: decoded_body,
          message_id: message_id.gsub(/Message-ID:\s*/i, "").strip
        }
      end
    end

    def fetch_messages(imap, ids)
      data = imap.uid_fetch(ids, [ "ENVELOPE", "UID", "FLAGS" ])
      return [] unless data

      data.map do |msg|
        env = msg.attr["ENVELOPE"]
        flags = msg.attr["FLAGS"]
        {
          uid: msg.attr["UID"],
          from: format_address(env.from),
          subject: env.subject.to_s,
          date: env.date.to_s,
          read: flags.include?(:Seen)
        }
      end
    end

    def with_imap
      imap = Net::IMAP.new("imap.gmail.com", port: 993, ssl: true)
      imap.login(gmail_address, gmail_password)
      result = yield(imap)
      imap.logout
      imap.disconnect
      result
    end

    # ─── SMTP ──────────────────────────────────────────────────────

    def smtp_send(to:, subject:, body:, in_reply_to: nil)
      mail = Mail.new do
        from    gmail_address
        to      to
        subject subject
        body    body
      end

      mail["In-Reply-To"] = in_reply_to if in_reply_to

      # Delegate to instance method for credentials
      address = gmail_address
      password = gmail_password

      smtp = Net::SMTP.new("smtp.gmail.com", 587)
      smtp.enable_starttls
      smtp.start("gmail.com", address, password, :login) do |server|
        server.send_message(mail.to_s, address, to)
      end
    end

    def format_address(addresses)
      return "" unless addresses
      addresses.map { |a| "#{a.name} <#{a.mailbox}@#{a.host}>" }.join(", ")
    end

    # ─── Credentials ───────────────────────────────────────────────

    def gmail_address
      @gmail_address ||= vault_get("google", "gmail_address") || ENV["GMAIL_ADDRESS"]
    end

    def gmail_password
      @gmail_password ||= vault_get("google", "gmail_app_password") || ENV["GMAIL_APP_PASSWORD"]
    end

    def vault_get(namespace, key)
      entry = VaultEntry.find_by(namespace: namespace, key: key)
      entry&.value
    end
  end
end
