# frozen_string_literal: true

require "net/http"
require "json"

module Channels
  # LINE integration via the Messaging API.
  #
  # Inbound arrives as a webhook POST to /webhooks/line carrying one or more
  # events; we create + enqueue one InboundMessage per text/audio message event
  # and return :processed, so WebhooksController does not also enqueue (it only
  # enqueues when :inbound_message is present). Outbound replies use the push API.
  #
  # Vault credentials (namespace "channel_credentials"):
  #   line_channel_access_token  bot token for API calls (push + media download)
  #   line_channel_secret        secret used to verify the X-Line-Signature header
  class LineAdapter < BaseAdapter
    def receive(message)
      payload = message.deep_symbolize_keys
      events = payload[:events] || []
      processed = 0

      events.each do |event|
        next unless event[:type] == "message"

        source = event[:source] || {}
        msg = event[:message] || {}
        to = source[:groupId] || source[:roomId] || source[:userId]

        content =
          case msg[:type]
          when "text"  then msg[:text].to_s
          when "audio" then transcribe_line_audio(msg[:id])
          end
        next if content.blank?

        inbound = log_inbound_message(
          external_id: msg[:id].to_s,
          sender: to.to_s, # reply target is the group/room/user
          content: content,
          metadata: { line_user: source[:userId], source_type: source[:type] }
        )
        InboundMessageJob.perform_later(inbound.id)
        processed += 1
      rescue ActiveRecord::RecordNotUnique
        next # duplicate webhook retry — already handled
      end

      ServiceResponse.success(data: { processed: processed })
    rescue StandardError => e
      ServiceResponse.failure(error: "LINE receive failed: #{e.message}")
    end

    def send_message(to:, content:, **_options)
      token = channel_access_token
      return ServiceResponse.failure(error: "LINE channel access token not configured") unless token

      uri = URI("https://api.line.me/v2/bot/message/push")
      body = { to: to, messages: [ { type: "text", text: content } ] }
      response = post_json(uri, body, token)

      if response[:code] == "200"
        outbound = log_outbound_message(recipient: to, content: content)
        ServiceResponse.success(data: { outbound_message: outbound })
      else
        ServiceResponse.failure(error: "LINE API: #{response[:body]}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "LINE send failed: #{e.message}")
    end

    # Verify the X-Line-Signature header: Base64(HMAC-SHA256(channel_secret, raw_post)).
    def verify_webhook(request)
      secret = channel_secret
      return true if secret.blank? # not configured → allow (dev)

      expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, request.raw_post))
      provided = request.headers["X-Line-Signature"].to_s
      ActiveSupport::SecurityUtils.secure_compare(expected, provided)
    end

    private

    def channel_access_token
      VaultEntry.find_by(namespace: "channel_credentials", key: "line_channel_access_token")&.value
    end

    def channel_secret
      VaultEntry.find_by(namespace: "channel_credentials", key: "line_channel_secret")&.value
    end

    # Download a LINE audio message and transcribe it via the shared STT hook.
    def transcribe_line_audio(message_id)
      token = channel_access_token
      return nil if token.blank? || message_id.blank?

      uri = URI("https://api-data.line.me/v2/bot/message/#{message_id}/content")
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{token}"
      data = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req).body }

      tmp = Rails.root.join("tmp", "line_audio_#{message_id}.m4a")
      File.binwrite(tmp, data)
      begin
        transcribe_audio(tmp.to_s)
      ensure
        File.delete(tmp) if File.exist?(tmp)
      end
    rescue StandardError => e
      Rails.logger.warn("[line] audio download failed: #{e.message}")
      nil
    end

    def post_json(uri, body, token)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 15

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req["Authorization"] = "Bearer #{token}"
      req.body = body.to_json

      response = http.request(req)
      { code: response.code, body: response.body }
    end
  end
end
