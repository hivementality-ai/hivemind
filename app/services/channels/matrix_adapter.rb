# frozen_string_literal: true

require "net/http"
require "json"

module Channels
  # Matrix integration via the Application Service (AS) API.
  #
  # The homeserver pushes events to us as transactions (PUT .../transactions/:txn,
  # routed to WebhooksController#receive with channel_type=matrix) and we send
  # replies back over the client-server API. Config (channel.config):
  #   homeserver_url  e.g. "https://matrix.org"
  #   user_id         the AS bot user, e.g. "@hivemind:matrix.org"
  #   hs_token        token the homeserver authenticates *to us* with
  # Vault credential "matrix_access_token" is the bot's client-server token.
  class MatrixAdapter < BaseAdapter
    # A transaction can carry several events. We create + enqueue one InboundMessage
    # per room text/audio message and return :processed, so WebhooksController does
    # not also enqueue (it only enqueues when :inbound_message is present).
    def receive(message)
      payload = message.deep_symbolize_keys
      events = payload[:events] || []
      processed = 0

      events.each do |event|
        next unless event[:type] == "m.room.message"

        room_id = event[:room_id].to_s
        sender  = event[:sender].to_s
        body    = event.dig(:content, :body).to_s
        msgtype = event.dig(:content, :msgtype)

        next if sender == bot_user_id # ignore our own echoes

        content = body
        if msgtype == "m.audio" && (url = event.dig(:content, :url))
          transcript = transcribe_matrix_audio(url)
          content = transcript if transcript.present?
        end
        next if content.blank?

        inbound = log_inbound_message(
          external_id: event[:event_id].to_s,
          sender: room_id, # reply target is the room
          content: content,
          metadata: { matrix_user: sender, room_id: room_id, msgtype: msgtype }
        )
        InboundMessageJob.perform_later(inbound.id)
        processed += 1
      rescue ActiveRecord::RecordNotUnique
        next # duplicate transaction retry — already handled
      end

      ServiceResponse.success(data: { processed: processed })
    rescue StandardError => e
      ServiceResponse.failure(error: "Matrix receive failed: #{e.message}")
    end

    def send_message(to:, content:, **_options)
      token = access_token
      return ServiceResponse.failure(error: "Matrix access token not configured") unless token

      txn = "hm#{Time.current.to_i}#{rand(1000)}"
      uri = URI("#{homeserver_url}/_matrix/client/v3/rooms/#{CGI.escape(to)}/send/m.room.message/#{txn}")
      body = { msgtype: "m.text", body: content }

      response = put_json(uri, body, token)
      if response["event_id"]
        outbound = log_outbound_message(recipient: to, content: content, metadata: { event_id: response["event_id"] })
        ServiceResponse.success(data: { outbound_message: outbound, response: response })
      else
        ServiceResponse.failure(error: "Matrix API: #{response["error"] || response}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Matrix send failed: #{e.message}")
    end

    # The homeserver authenticates to us with hs_token (query param or Bearer header).
    def verify_webhook(request)
      expected = channel.config&.dig("hs_token")
      return true if expected.blank? # not configured → allow (dev)

      provided = request.query_parameters["access_token"] ||
                 request.headers["Authorization"].to_s.sub(/\ABearer /, "")
      ActiveSupport::SecurityUtils.secure_compare(provided.to_s, expected.to_s)
    end

    private

    def homeserver_url
      (channel.config&.dig("homeserver_url") || "https://matrix.org").chomp("/")
    end

    def bot_user_id
      channel.config&.dig("user_id").to_s
    end

    def access_token
      VaultEntry.find_by(namespace: "channel_credentials", key: "matrix_access_token")&.value
    end

    # Download an mxc:// media URL and transcribe it via the shared STT hook.
    def transcribe_matrix_audio(mxc_url)
      server, media_id = mxc_url.to_s.sub("mxc://", "").split("/", 2)
      return nil unless server && media_id

      uri = URI("#{homeserver_url}/_matrix/media/v3/download/#{server}/#{media_id}")
      data = Net::HTTP.get(uri)
      tmp = Rails.root.join("tmp", "matrix_audio_#{media_id}.ogg")
      File.binwrite(tmp, data)
      begin
        transcribe_audio(tmp.to_s)
      ensure
        File.delete(tmp) if File.exist?(tmp)
      end
    rescue StandardError => e
      Rails.logger.warn("[matrix] audio download failed: #{e.message}")
      nil
    end

    def put_json(uri, body, token)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 15

      req = Net::HTTP::Put.new(uri)
      req["Content-Type"] = "application/json"
      req["Authorization"] = "Bearer #{token}"
      req.body = body.to_json

      JSON.parse(http.request(req).body)
    rescue StandardError => e
      { "error" => e.message }
    end
  end
end
