# frozen_string_literal: true

require "net/http"
require "json"

module Channels
  # Mattermost integration: inbound via Outgoing Webhooks, outbound via REST API v4.
  #
  # Mattermost posts to an Outgoing Webhook (form-encoded, routed to
  # WebhooksController#receive with channel_type=mattermost) when a trigger word
  # matches; we reply back over the v4 API with a bot access token. Config
  # (channel.config):
  #   base_url        e.g. "https://mattermost.example.com"
  #   outgoing_token  shared token Mattermost sends so we can verify inbound
  #   bot_user_id     optional — our own user id, to ignore the bot's echoes
  # Vault credentials:
  #   mattermost_bot_token         bot access token for the v4 API (outbound)
  #   mattermost_outgoing_token    optional alt location for the inbound token
  class MattermostAdapter < BaseAdapter
    def receive(message)
      payload = message.deep_symbolize_keys

      text = payload[:text].to_s
      return ServiceResponse.success(data: { skipped: true }) if text.blank?

      user_id = payload[:user_id].to_s
      return ServiceResponse.success(data: { skipped: true }) if own_message?(user_id)

      inbound = log_inbound_message(
        external_id: payload[:post_id].to_s,
        sender: payload[:channel_id].to_s, # reply target is the channel
        content: text,
        metadata: {
          user_id: user_id,
          user_name: payload[:user_name].to_s,
          channel_name: payload[:channel_name].to_s,
          team_id: payload[:team_id].to_s
        }
      )

      ServiceResponse.success(data: { inbound_message: inbound })
    rescue ActiveRecord::RecordNotUnique
      ServiceResponse.success(data: { skipped: true })
    rescue StandardError => e
      ServiceResponse.failure(error: "Mattermost receive failed: #{e.message}")
    end

    def send_message(to:, content:, **_options)
      token = bot_token
      return ServiceResponse.failure(error: "Mattermost bot token not configured") unless token

      uri = URI("#{base_url}/api/v4/posts")
      response = post_json(uri, { channel_id: to, message: content }, token)

      if response["id"]
        outbound = log_outbound_message(recipient: to, content: content, metadata: { post_id: response["id"] })
        ServiceResponse.success(data: { outbound_message: outbound, response: response })
      else
        ServiceResponse.failure(error: "Mattermost API: #{response["message"] || response["error"] || response}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Mattermost send failed: #{e.message}")
    end

    # Mattermost sends the outgoing-webhook token in the request body.
    def verify_webhook(request)
      expected = outgoing_token
      return true if expected.blank? # not configured → allow (dev)

      provided = request.params["token"] || request.request_parameters["token"]
      ActiveSupport::SecurityUtils.secure_compare(provided.to_s, expected.to_s)
    end

    private

    def base_url
      channel.config&.dig("base_url").to_s.chomp("/")
    end

    def own_message?(user_id)
      bot = channel.config&.dig("bot_user_id").to_s
      bot.present? && bot == user_id
    end

    def bot_token
      VaultEntry.find_by(namespace: "channel_credentials", key: "mattermost_bot_token")&.value
    end

    def outgoing_token
      VaultEntry.find_by(namespace: "channel_credentials", key: "mattermost_outgoing_token")&.value.presence ||
        channel.config&.dig("outgoing_token")
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

      JSON.parse(http.request(req).body)
    rescue StandardError => e
      { "error" => e.message }
    end
  end
end
