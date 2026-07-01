# frozen_string_literal: true

require "net/http"
require "json"

module Channels
  class WhatsappAdapter < BaseAdapter
    # Supports two modes:
    # 1. Connector bridge (Baileys) — default, talks to the Node.js connector sidecar
    # 2. Meta Cloud API — set config["mode"] = "cloud_api" for official API

    def receive(message)
      payload = message.deep_symbolize_keys

      entry = payload.dig(:entry, 0) || {}
      change = entry.dig(:changes, 0, :value) || {}
      msg = change.dig(:messages, 0)
      return ServiceResponse.success(data: { skipped: true }) unless msg

      # Transcribe voice messages via STT
      content = if msg[:type] == "audio" && msg.dig(:audio, :file_path)
        result = transcribe_audio(msg.dig(:audio, :file_path))
        result || msg.dig(:text, :body).to_s
      else
        msg.dig(:text, :body).to_s
      end

      inbound = log_inbound_message(
        external_id: msg[:id].to_s,
        sender: msg[:from].to_s,
        content: content,
        metadata: {
          type: msg[:type],
          timestamp: msg[:timestamp],
          phone_number_id: change[:metadata]&.dig(:phone_number_id),
          contact_name: change.dig(:contacts, 0, :profile, :name)
        }
      )

      ServiceResponse.success(data: { inbound_message: inbound })
    rescue StandardError => e
      ServiceResponse.failure(error: "WhatsApp receive failed: #{e.message}")
    end

    def send_message(to:, content:, **options)
      if cloud_api_mode?
        send_via_cloud_api(to: to, content: content, **options)
      else
        send_via_connector(to: to, content: content, **options)
      end
    end

    def verify_webhook(request)
      # Connector bridge doesn't use signatures (internal network)
      return true unless cloud_api_mode?

      app_secret = channel.config&.dig("app_secret")
      return true unless app_secret

      signature = request.headers["X-Hub-Signature-256"]&.sub("sha256=", "")
      return false unless signature

      verify_hmac_signature(payload: request.raw_post, signature: signature)
    end

    private

    def cloud_api_mode?
      channel.config&.dig("mode") == "cloud_api"
    end

    def connector_url
      channel.config&.dig("connector_url") || "http://connector:3002"
    end

    # ─── Connector Bridge (Baileys) ─────────────────────────────────

    def send_via_connector(to:, content:, **_options)
      uri = URI("#{connector_url}/send")
      # Strip WhatsApp JID suffix — connector expects plain phone number
      clean_to = to.to_s.gsub(/@s\.whatsapp\.net\z/, "").gsub(/\D/, "")
      body = { to: clean_to, message: content }

      response = post_json(uri, body)

      if response["status"] == "sent"
        outbound = log_outbound_message(recipient: to, content: content)
        ServiceResponse.success(data: { outbound_message: outbound })
      else
        ServiceResponse.failure(error: "Connector error: #{response["error"] || response}")
      end
    rescue Errno::ECONNREFUSED
      ServiceResponse.failure(error: "WhatsApp connector not running at #{connector_url}")
    rescue StandardError => e
      ServiceResponse.failure(error: "WhatsApp send failed: #{e.message}")
    end

    # ─── Meta Cloud API ─────────────────────────────────────────────

    def send_via_cloud_api(to:, content:, **_options)
      token = access_token
      phone_id = phone_number_id
      return ServiceResponse.failure(error: "WhatsApp Cloud API credentials not configured") unless token && phone_id

      uri = URI("https://graph.facebook.com/v21.0/#{phone_id}/messages")
      body = {
        messaging_product: "whatsapp",
        to: to.gsub(/\D/, ""),
        type: "text",
        text: { body: content }
      }

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Content-Type"] = "application/json"
      req.body = body.to_json

      response = JSON.parse(http.request(req).body)

      if response["messages"]
        outbound = log_outbound_message(
          recipient: to,
          content: content,
          metadata: { wamid: response.dig("messages", 0, "id") }
        )
        ServiceResponse.success(data: { outbound_message: outbound })
      else
        ServiceResponse.failure(error: "WhatsApp API: #{response.dig("error", "message") || response}")
      end
    end

    def access_token
      entry = VaultEntry.find_by(namespace: "channel_credentials", key: "whatsapp_access_token")
      entry&.value
    end

    def phone_number_id
      channel.config&.dig("phone_number_id")
    end

    def post_json(uri, body)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 30

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body = body.to_json

      JSON.parse(http.request(req).body)
    rescue StandardError => e
      { "error" => e.message }
    end
  end
end
