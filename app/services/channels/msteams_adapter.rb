# frozen_string_literal: true

require "net/http"
require "json"

module Channels
  # Microsoft Teams integration via the Bot Framework.
  #
  # Teams POSTs an Activity JSON to our messaging endpoint
  # (WebhooksController#receive with channel_type=msteams). Replies go back over
  # the Bot Connector REST API, which needs BOTH the activity's serviceUrl and
  # its conversation id, so the reply target is encoded as "serviceUrl|conversationId".
  #
  # Config (channel.config):
  #   app_id   the Azure Bot / App Registration client id
  # Vault credential "msteams_app_password" is the app client secret.
  class MsteamsAdapter < BaseAdapter
    TOKEN_URL = "https://login.microsoftonline.com/botframework.com/oauth2/v2.0/token"

    def receive(message)
      payload = message.deep_symbolize_keys
      return ServiceResponse.success(data: { skipped: true }) unless payload[:type] == "message"

      content = payload[:text].to_s.gsub(%r{<at>.*?</at>}, "").strip
      return ServiceResponse.success(data: { skipped: true }) if content.blank?

      service_url     = payload[:serviceUrl].to_s
      conversation_id = payload.dig(:conversation, :id).to_s

      inbound = log_inbound_message(
        external_id: payload[:id].to_s,
        sender: "#{service_url}|#{conversation_id}", # reply needs both
        content: content,
        metadata: {
          service_url: service_url,
          conversation_id: conversation_id,
          from_id: payload.dig(:from, :id),
          from_name: payload.dig(:from, :name),
          activity_id: payload[:id]
        }
      )

      ServiceResponse.success(data: { inbound_message: inbound })
    rescue ActiveRecord::RecordNotUnique
      ServiceResponse.success(data: { skipped: true })
    rescue StandardError => e
      ServiceResponse.failure(error: "MS Teams receive failed: #{e.message}")
    end

    def send_message(to:, content:, **_options)
      token = access_token
      return ServiceResponse.failure(error: "MS Teams access token not available") unless token

      service_url, conversation_id = to.split("|", 2)
      uri = URI("#{service_url.to_s.chomp("/")}/v3/conversations/#{conversation_id}/activities")
      response = post_json(uri, { type: "message", text: content }, token)

      if response["id"]
        outbound = log_outbound_message(recipient: to, content: content, metadata: { activity_id: response["id"] })
        ServiceResponse.success(data: { outbound_message: outbound, response: response })
      else
        ServiceResponse.failure(error: "MS Teams API: #{response["error"] || response}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "MS Teams send failed: #{e.message}")
    end

    # ponytail: v1 only checks an Authorization Bearer header is present when an
    # app_id is configured. Full Bot Framework JWT signature verification against
    # the OpenID metadata is the documented upgrade path.
    def verify_webhook(request)
      return true if channel.config&.dig("app_id").blank? # not configured → allow (dev)

      request.headers["Authorization"].to_s.start_with?("Bearer ")
    end

    private

    def access_token
      return @access_token if @access_token && @token_expires_at && Time.current < @token_expires_at

      app_id       = channel.config&.dig("app_id")
      app_password = VaultEntry.find_by(namespace: "channel_credentials", key: "msteams_app_password")&.value
      return nil if app_id.blank? || app_password.blank?

      response = request_token(app_id, app_password)
      return nil unless response["access_token"]

      @access_token = response["access_token"]
      @token_expires_at = Time.current + (response["expires_in"].to_i - 60).clamp(0, 86_400).seconds
      @access_token
    end

    def request_token(app_id, app_password)
      uri = URI(TOKEN_URL)
      http = build_http(uri)
      req = Net::HTTP::Post.new(uri)
      req.set_form_data(
        "grant_type" => "client_credentials",
        "client_id" => app_id,
        "client_secret" => app_password,
        "scope" => "https://api.botframework.com/.default"
      )
      JSON.parse(http.request(req).body)
    rescue StandardError => e
      { "error" => e.message }
    end

    def post_json(uri, body, token)
      http = build_http(uri)
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req["Authorization"] = "Bearer #{token}"
      req.body = body.to_json
      JSON.parse(http.request(req).body.presence || "{}")
    rescue StandardError => e
      { "error" => e.message }
    end

    def build_http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 15
      http
    end
  end
end
