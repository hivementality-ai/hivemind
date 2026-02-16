# frozen_string_literal: true

require "net/smtp"
require "mail"

module Tools
  class EmailExecutor < BaseExecutor
    # Generic SMTP email tool. Works with any SMTP provider:
    # Mailtrap, SendGrid, Mailgun, Amazon SES, Gmail, etc.
    #
    # Credentials stored in vault:
    #   email/smtp_host       — e.g. live.smtp.mailtrap.io
    #   email/smtp_port       — e.g. 587
    #   email/smtp_username   — SMTP username
    #   email/smtp_password   — SMTP password
    #   email/from_address    — default sender address
    #   email/from_name       — display name (optional)

    def call
      action = input["action"].to_s.strip

      case action
      when "send"
        send_email
      when "send_html"
        send_html_email
      when "config"
        show_config
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Supported: send, send_html, config")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Email error: #{e.message}")
    end

    private

    def send_email
      to = input["to"].to_s.strip
      subject = input["subject"].to_s.strip
      body = input["body"].to_s.strip

      return ServiceResponse.failure(error: "to, subject, and body required") if [ to, subject, body ].any?(&:empty?)

      cc = input["cc"].to_s.strip.presence
      bcc = input["bcc"].to_s.strip.presence
      reply_to = input["reply_to"].to_s.strip.presence

      mail = build_mail(to: to, subject: subject, cc: cc, bcc: bcc, reply_to: reply_to) do |m|
        m.text_part do
          body body
        end
      end

      deliver(mail)
      recipients = [ to, cc, bcc ].compact.join(", ")
      ServiceResponse.success(data: { output: "Email sent to #{recipients}: #{subject}", exit_code: 0 })
    end

    def send_html_email
      to = input["to"].to_s.strip
      subject = input["subject"].to_s.strip
      html = input["html"].to_s.strip
      text = input["text"].to_s.strip.presence

      return ServiceResponse.failure(error: "to, subject, and html required") if [ to, subject, html ].any?(&:empty?)

      cc = input["cc"].to_s.strip.presence
      bcc = input["bcc"].to_s.strip.presence
      reply_to = input["reply_to"].to_s.strip.presence

      mail = build_mail(to: to, subject: subject, cc: cc, bcc: bcc, reply_to: reply_to) do |m|
        m.text_part { body(text || "Please view this email in an HTML-capable client.") }
        m.html_part do
          content_type "text/html; charset=UTF-8"
          body html
        end
      end

      deliver(mail)
      ServiceResponse.success(data: { output: "HTML email sent to #{to}: #{subject}", exit_code: 0 })
    end

    def show_config
      configured = smtp_host.present? && smtp_username.present?
      output = if configured
                 "SMTP configured: #{smtp_host}:#{smtp_port} (#{from_address})"
      else
                 "SMTP not configured. Set credentials in Integrations > Email."
      end
      ServiceResponse.success(data: { output: output, exit_code: 0 })
    end

    # ─── Mail building ─────────────────────────────────────────────

    def build_mail(to:, subject:, cc: nil, bcc: nil, reply_to: nil, &block)
      from_addr = from_address
      from_display = from_name

      Mail.new do
        from     from_display.present? ? "#{from_display} <#{from_addr}>" : from_addr
        to       to
        subject  subject
        cc       cc if cc
        bcc      bcc if bcc
        reply_to reply_to if reply_to

        instance_eval(&block) if block
      end
    end

    def deliver(mail)
      smtp = Net::SMTP.new(smtp_host, smtp_port)

      if smtp_port.to_i == 465
        smtp.enable_tls
      else
        smtp.enable_starttls_auto
      end

      smtp.start(smtp_host, smtp_username, smtp_password, :login) do |server|
        server.send_message(mail.to_s, from_address, mail.destinations)
      end
    end

    # ─── Credentials ───────────────────────────────────────────────

    def smtp_host
      @smtp_host ||= vault_get("email", "smtp_host") || ENV["SMTP_HOST"]
    end

    def smtp_port
      @smtp_port ||= (vault_get("email", "smtp_port") || ENV["SMTP_PORT"] || "587").to_i
    end

    def smtp_username
      @smtp_username ||= vault_get("email", "smtp_username") || ENV["SMTP_USERNAME"]
    end

    def smtp_password
      @smtp_password ||= vault_get("email", "smtp_password") || ENV["SMTP_PASSWORD"]
    end

    def from_address
      @from_address ||= vault_get("email", "from_address") || ENV["SMTP_FROM_ADDRESS"] || smtp_username
    end

    def from_name
      @from_name ||= vault_get("email", "from_name") || ENV["SMTP_FROM_NAME"]
    end

    def vault_get(namespace, key)
      entry = VaultEntry.find_by(namespace: namespace, key: key)
      entry&.value
    end
  end
end
