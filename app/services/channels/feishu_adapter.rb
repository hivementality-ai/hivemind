# frozen_string_literal: true

require "net/http"
require "json"

module Channels
  # Feishu / Lark integration via the Open Platform event subscription (v2).
  #
  # The platform pushes events to WebhooksController#receive (channel_type=feishu).
  # Two inbound cases are handled:
  #   1. url_verification — echo back the challenge (controller renders it).
  #   2. im.message.receive_v1 — a chat message; we reply to event.message.chat_id.
  #
  # Config (channel.config):
  #   app_id              the app's App ID (non-secret)
  #   verification_token  the event subscription "Verification Token"
  #   base_url            e.g. "https://open.feishu.cn" (China) or
  #                       "https://open.larksuite.com" (international)
  # Vault credential "feishu_app_secret" is the app secret used to mint a
  # tenant_access_token for outbound sends.
  #
  # ponytail: plaintext events + verification token only. Encrypt Key payload
  # encryption and full request signature verification are a follow-up.
  class FeishuAdapter < BaseAdapter
    DEFAULT_BASE_URL = "https://open.feishu.cn"

    def receive(message)
      payload = message.deep_symbolize_keys

      # URL verification handshake — controller echoes the challenge.
      if payload[:type] == "url_verification"
        return ServiceResponse.success(data: { challenge: payload[:challenge] })
      end

      header = payload[:header] || {}
      return ServiceResponse.success(data: { skipped: true }) unless header[:event_type] == "im.message.receive_v1"

      event = payload[:event] || {}
      sender = event[:sender] || {}
      return ServiceResponse.success(data: { skipped: true }) if sender[:sender_type] == "app" # our own / bot

      msg = event[:message] || {}
      return ServiceResponse.success(data: { skipped: true }) unless msg[:message_type] == "text"

      text = JSON.parse(msg[:content].to_s)["text"].to_s
      return ServiceResponse.success(data: { skipped: true }) if text.blank?

      inbound = log_inbound_message(
        external_id: msg[:message_id].to_s,
        sender: msg[:chat_id].to_s, # reply target is the chat
        content: text,
        metadata: {
          open_id: sender.dig(:sender_id, :open_id),
          chat_type: msg[:chat_type]
        }
      )

      ServiceResponse.success(data: { inbound_message: inbound })
    rescue StandardError => e
      ServiceResponse.failure(error: "Feishu receive failed: #{e.message}")
    end

    def send_message(to:, content:, **_options)
      token = tenant_access_token
      return ServiceResponse.failure(error: "Feishu tenant_access_token unavailable") unless token

      uri = URI("#{base_url}/open-apis/im/v1/messages?receive_id_type=chat_id")
      body = {
        receive_id: to,
        msg_type: "text",
        content: { text: content }.to_json
      }

      response = post_json(uri, body, token)
      if response["code"]&.zero?
        outbound = log_outbound_message(recipient: to, content: content, metadata: { message_id: response.dig("data", "message_id") })
        ServiceResponse.success(data: { outbound_message: outbound, response: response })
      else
        ServiceResponse.failure(error: "Feishu API: #{response["msg"] || response}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Feishu send failed: #{e.message}")
    end

    # The platform sends header.token == the event "Verification Token".
    def verify_webhook(request)
      expected = channel.config&.dig("verification_token")
      return true if expected.blank? # not configured → allow (dev)

      payload = parse_request(request)
      return true if payload[:type] == "url_verification" # handshake carries no event token

      provided = payload.dig(:header, :token).to_s
      ActiveSupport::SecurityUtils.secure_compare(provided, expected.to_s)
    end

    private

    def base_url
      (channel.config&.dig("base_url").presence || DEFAULT_BASE_URL).chomp("/")
    end

    def app_secret
      VaultEntry.find_by(namespace: "channel_credentials", key: "feishu_app_secret")&.value
    end

    # Mint and cache a tenant_access_token, refreshing shortly before it expires.
    def tenant_access_token
      return @tenant_access_token if @tenant_access_token && @token_expires_at && Time.current < @token_expires_at

      app_id = channel.config&.dig("app_id")
      secret = app_secret
      return nil if app_id.blank? || secret.blank?

      uri = URI("#{base_url}/open-apis/auth/v3/tenant_access_token/internal")
      response = post_json(uri, { app_id: app_id, app_secret: secret }, nil)
      token = response["tenant_access_token"]
      return nil unless token

      # Refresh 60s early to avoid using a just-expired token mid-flight.
      @token_expires_at = Time.current + (response["expire"].to_i - 60).clamp(0, Float::INFINITY).seconds
      @tenant_access_token = token
    end

    def post_json(uri, body, token)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 15

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json; charset=utf-8"
      req["Authorization"] = "Bearer #{token}" if token
      req.body = body.to_json

      JSON.parse(http.request(req).body)
    rescue StandardError => e
      { "error" => e.message }
    end

    def parse_request(request)
      JSON.parse(request.raw_post).deep_symbolize_keys
    rescue StandardError
      {}
    end
  end
end
