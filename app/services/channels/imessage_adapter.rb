# frozen_string_literal: true

require "net/http"
require "json"
require "cgi"
require "securerandom"

module Channels
  # iMessage via a self-hosted BlueBubbles server.
  #
  # Apple has no official API, so this adapter talks to BlueBubbles
  # (https://bluebubbles.app) — a macOS server that exposes a REST API and
  # fires outgoing webhooks. A BlueBubbles server must be running on a Mac.
  #
  # Inbound: BlueBubbles POSTs to /webhooks/imessage with
  #   { type: "new-message", data: { guid, text, isFromMe, handle: { address }, chats: [{ guid }] } }
  # We reply to the chat GUID (data.chats[0].guid).
  #
  # Config (channel.config):
  #   server_url      BlueBubbles base URL, e.g. "http://localhost:1234" or a tunnel URL
  #   webhook_secret  optional shared secret checked on inbound (?secret=...)
  # Vault credential "bluebubbles_password" is the BlueBubbles server password.
  class ImessageAdapter < BaseAdapter
    def receive(message)
      payload = message.deep_symbolize_keys
      return ServiceResponse.success(data: { skipped: true }) unless payload[:type] == "new-message"

      data = payload[:data] || {}
      return ServiceResponse.success(data: { skipped: true }) if data[:isFromMe]

      content = data[:text].to_s
      return ServiceResponse.success(data: { skipped: true }) if content.blank?

      chat_guid = data.dig(:chats, 0, :guid).to_s

      inbound = log_inbound_message(
        external_id: data[:guid].to_s,
        sender: chat_guid, # reply target is the chat
        content: content,
        metadata: { address: data.dig(:handle, :address) }
      )

      ServiceResponse.success(data: { inbound_message: inbound })
    rescue ActiveRecord::RecordNotUnique
      ServiceResponse.success(data: { skipped: true })
    rescue StandardError => e
      ServiceResponse.failure(error: "iMessage receive failed: #{e.message}")
    end

    def send_message(to:, content:, **_options)
      password = server_password
      return ServiceResponse.failure(error: "BlueBubbles password not configured") if password.blank?

      uri = URI("#{server_url}/api/v1/message/text?password=#{CGI.escape(password)}")
      body = { chatGuid: to, tempGuid: SecureRandom.uuid, message: content, method: "apple-script" }

      response = post_json(uri, body)
      if response["status"] == 200 || response["data"]
        outbound = log_outbound_message(recipient: to, content: content, metadata: { response: response["status"] })
        ServiceResponse.success(data: { outbound_message: outbound, response: response })
      else
        ServiceResponse.failure(error: "BlueBubbles API: #{response["error"] || response["message"] || response}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "iMessage send failed: #{e.message}")
    end

    # BlueBubbles webhooks aren't signed. If a shared secret is configured,
    # require it as a ?secret= query param; otherwise allow (permissive).
    def verify_webhook(request)
      secret = channel.config&.dig("webhook_secret")
      return true if secret.blank?

      provided = request.query_parameters["secret"] || request.params["secret"]
      ActiveSupport::SecurityUtils.secure_compare(provided.to_s, secret.to_s)
    end

    private

    def server_url
      channel.config&.dig("server_url").to_s.chomp("/")
    end

    def server_password
      VaultEntry.find_by(namespace: "channel_credentials", key: "bluebubbles_password")&.value
    end

    def post_json(uri, body)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 15

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body = body.to_json

      JSON.parse(http.request(req).body)
    rescue StandardError => e
      { "error" => e.message }
    end
  end
end
