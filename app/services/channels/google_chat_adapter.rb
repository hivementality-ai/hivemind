# frozen_string_literal: true

require "net/http"
require "json"
require "base64"
require "openssl"

module Channels
  # Google Chat integration via the Chat REST API.
  #
  # Inbound: Google pushes events to /webhooks/google_chat as JSON
  #   { type: "MESSAGE"|"ADDED_TO_SPACE"|..., message: { name, text, sender }, space: { name } }
  # We only handle type == "MESSAGE" from HUMAN senders. Replies go back to the
  # space, sent asynchronously over the REST API authenticated with a service
  # account (OAuth2 JWT-bearer, minted without a gem).
  #
  # Config (channel.config):
  #   verification_token  optional shared token matched against the bearer header
  #   require_auth        when truthy (and no verification_token), require an
  #                       Authorization header to be present
  # Vault credential "google_chat_sa_json" is the full service-account JSON key.
  class GoogleChatAdapter < BaseAdapter
    TOKEN_URI = "https://oauth2.googleapis.com/token"
    CHAT_API  = "https://chat.googleapis.com/v1"
    SCOPE     = "https://www.googleapis.com/auth/chat.bot"

    def receive(message)
      payload = message.deep_symbolize_keys
      return ServiceResponse.success(data: { skipped: true }) unless payload[:type] == "MESSAGE"

      sender_type = payload.dig(:message, :sender, :type)
      return ServiceResponse.success(data: { skipped: true }) if sender_type == "BOT"

      text = payload.dig(:message, :text).to_s
      return ServiceResponse.success(data: { skipped: true }) if text.blank?

      space = payload.dig(:space, :name).to_s
      inbound = log_inbound_message(
        external_id: payload.dig(:message, :name).to_s,
        sender: space, # reply target is the space
        content: text,
        metadata: { sender: payload.dig(:message, :sender, :displayName), space: space }
      )

      ServiceResponse.success(data: { inbound_message: inbound })
    rescue ActiveRecord::RecordNotUnique
      ServiceResponse.success(data: { skipped: true })
    rescue StandardError => e
      ServiceResponse.failure(error: "Google Chat receive failed: #{e.message}")
    end

    def send_message(to:, content:, **_options)
      token = access_token
      return ServiceResponse.failure(error: "Google Chat service account not configured") unless token

      uri = URI("#{CHAT_API}/#{to}/messages")
      response = post_json(uri, { text: content }, token)
      if response["name"]
        outbound = log_outbound_message(recipient: to, content: content, metadata: { name: response["name"] })
        ServiceResponse.success(data: { outbound_message: outbound, response: response })
      else
        ServiceResponse.failure(error: "Google Chat API: #{response["error"] || response}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Google Chat send failed: #{e.message}")
    end

    # Google sends "Authorization: Bearer <JWT>" issued by chat@system.gserviceaccount.com.
    # ponytail: v1 does a token/presence check; full JWT signature + issuer verification
    # against Google's public certs is the upgrade path.
    def verify_webhook(request)
      bearer = request.headers["Authorization"].to_s.sub(/\ABearer /, "")
      expected = channel.config&.dig("verification_token")
      return ActiveSupport::SecurityUtils.secure_compare(bearer, expected.to_s) if expected.present?

      return bearer.present? if channel.config&.dig("require_auth")

      true # not configured → allow
    end

    private

    def access_token
      return @access_token if @access_token && @access_token_expiry && Time.current < @access_token_expiry

      sa = service_account
      return nil unless sa

      assertion = signed_jwt(sa)
      response = post_form(URI(TOKEN_URI), {
        "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion" => assertion
      })
      token = response["access_token"]
      return nil unless token

      @access_token = token
      @access_token_expiry = Time.current + (response["expires_in"].to_i - 60).seconds
      @access_token
    end

    def service_account
      raw = VaultEntry.find_by(namespace: "channel_credentials", key: "google_chat_sa_json")&.value
      return nil if raw.blank?

      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end

    def signed_jwt(sa)
      now = Time.current.to_i
      header = base64url({ alg: "RS256", typ: "JWT" }.to_json)
      claims = base64url({
        iss: sa["client_email"],
        scope: SCOPE,
        aud: TOKEN_URI,
        iat: now,
        exp: now + 3600
      }.to_json)
      signing_input = "#{header}.#{claims}"
      signature = OpenSSL::PKey::RSA.new(sa["private_key"]).sign(OpenSSL::Digest::SHA256.new, signing_input)
      "#{signing_input}.#{base64url(signature)}"
    end

    def base64url(value)
      Base64.urlsafe_encode64(value, padding: false)
    end

    def post_json(uri, body, token)
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req["Authorization"] = "Bearer #{token}"
      req.body = body.to_json
      JSON.parse(http_for(uri).request(req).body)
    rescue StandardError => e
      { "error" => e.message }
    end

    def post_form(uri, params)
      req = Net::HTTP::Post.new(uri)
      req.set_form_data(params)
      JSON.parse(http_for(uri).request(req).body)
    rescue StandardError => e
      { "error" => e.message }
    end

    def http_for(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 15
      http
    end
  end
end
