# frozen_string_literal: true

require "digest"

module Channels
  # Email as a conversational channel.
  #
  # Inbound arrives as an "inbound parse" webhook POST from your mail provider
  # (Mailgun, SendGrid, Postmark, etc.) to /webhooks/email. We read the common
  # fields flexibly so most providers work without per-provider code. Outbound
  # replies are sent with ActionMailer using the app's configured SMTP.
  #
  # Config (channel.config):
  #   from_email      address replies are sent from, e.g. "agent@yourdomain.com"
  #   reply_subject   subject line for replies (optional)
  #   webhook_secret  optional shared secret checked on inbound (?secret= or header)
  class EmailAdapter < BaseAdapter
    def receive(message)
      payload = message.deep_symbolize_keys

      from    = first_present(payload, :from, :sender, :From, :"from-email")
      subject = first_present(payload, :subject, :Subject).to_s
      text    = first_present(payload, :text, :"body-plain", :"stripped-text", :plain, :body).to_s
      msg_id  = first_present(payload, :"message-id", :"Message-Id", :message_id).presence ||
                "email-#{Digest::SHA256.hexdigest("#{from}#{subject}#{text}")[0, 16]}"

      return ServiceResponse.success(data: { skipped: true }) if from.blank?

      content = subject.present? ? "Subject: #{subject}\n\n#{text}".strip : text

      # Audio attachment with a local path → transcribe (provider-dependent).
      attachments = payload[:attachments]
      if attachments.is_a?(Array)
        audio = attachments.find { |a| a[:content_type].to_s.start_with?("audio/") && a[:file_path].present? }
        if audio
          transcript = transcribe_audio(audio[:file_path])
          content = "#{content}\n\n[voice transcript] #{transcript}".strip if transcript.present?
        end
      end

      inbound = log_inbound_message(
        external_id: msg_id.to_s,
        sender: extract_address(from),
        content: content,
        metadata: { subject: subject, raw_from: from }
      )

      ServiceResponse.success(data: { inbound_message: inbound })
    rescue ActiveRecord::RecordNotUnique
      ServiceResponse.success(data: { skipped: true })
    rescue StandardError => e
      ServiceResponse.failure(error: "Email receive failed: #{e.message}")
    end

    def send_message(to:, content:, **options)
      from    = channel.config&.dig("from_email").presence || "hivemind@localhost"
      subject = options[:subject].presence || channel.config&.dig("reply_subject").presence ||
                "Message from your Hivemind agent"

      ChannelMailer.agent_reply(to: to, from: from, subject: subject, body: content).deliver_now

      outbound = log_outbound_message(recipient: to, content: content, metadata: { subject: subject })
      ServiceResponse.success(data: { outbound_message: outbound })
    rescue StandardError => e
      ServiceResponse.failure(error: "Email send failed: #{e.message}")
    end

    def verify_webhook(request)
      secret = channel.config&.dig("webhook_secret")
      return true if secret.blank? # not configured → allow

      provided = request.query_parameters["secret"] || request.headers["X-Webhook-Secret"]
      ActiveSupport::SecurityUtils.secure_compare(provided.to_s, secret.to_s)
    end

    private

    def first_present(hash, *keys)
      keys.each { |k| v = hash[k]; return v if v.present? }
      nil
    end

    # "Alice <alice@example.com>" → "alice@example.com"
    def extract_address(value)
      value.to_s[/[^<>\s]+@[^<>\s]+/] || value.to_s
    end
  end
end
