# frozen_string_literal: true

require "net/http"
require "json"

module Channels
  class SlackAdapter < BaseAdapter
    BASE_URL = "https://slack.com/api"

    def receive(message)
      payload = message.deep_symbolize_keys

      # Handle URL verification challenge
      if payload[:type] == "url_verification"
        return ServiceResponse.success(data: { challenge: payload[:challenge] })
      end

      # Handle event callbacks
      event = payload[:event]
      return ServiceResponse.success(data: { skipped: true }) unless event
      return ServiceResponse.success(data: { skipped: true }) if event[:bot_id] # Ignore bot messages

      # Extract bot_user_id for routing assistance
      metadata = {
        channel_id: event[:channel],
        thread_ts: event[:thread_ts],
        event_type: event[:type],
        team_id: payload[:team_id]
      }

      # Add bot_user_id if available from authorization headers
      if payload.dig(:authorizations, 0, :user_id)
        metadata[:bot_user_id] = payload.dig(:authorizations, 0, :user_id)
      end

      inbound = log_inbound_message(
        external_id: event[:ts].to_s,
        sender: event[:user].to_s,
        content: event[:text].to_s,
        metadata: metadata
      )

      ServiceResponse.success(data: { inbound_message: inbound })
    rescue StandardError => e
      ServiceResponse.failure(error: "Slack receive failed: #{e.message}")
    end

    def send_message(to:, content:, agent: nil, **options)
      token = resolve_bot_token(agent)
      return ServiceResponse.failure(error: "Slack bot token not configured") unless token

      body = {
        channel: to,
        text: content
      }
      body[:thread_ts] = options[:thread_ts] if options[:thread_ts]
      body[:blocks] = options[:blocks] if options[:blocks]
      body[:unfurl_links] = false if options[:no_unfurl]

      response = slack_post("chat.postMessage", body, token)

      if response["ok"]
        outbound = log_outbound_message(
          recipient: to,
          content: content,
          metadata: { ts: response["ts"], channel: response["channel"], agent_id: agent&.id }
        )
        ServiceResponse.success(data: { outbound_message: outbound, response: response })
      else
        ServiceResponse.failure(error: "Slack API: #{response["error"]}")
      end
    end

    def react(message_id:, emoji:, channel_id: nil)
      token = bot_token
      return ServiceResponse.failure(error: "Bot token not configured") unless token

      target_channel = channel_id || channel.config&.dig("default_channel_id")
      return ServiceResponse.failure(error: "No channel_id for reaction") unless target_channel

      body = {
        channel: target_channel,
        timestamp: message_id,
        name: emoji.gsub(/^:|:$/, "") # Strip colons if present
      }

      response = slack_post("reactions.add", body, token)
      response["ok"] ? ServiceResponse.success(data: {}) : ServiceResponse.failure(error: response["error"])
    end

    def verify_webhook(request)
      # In Socket Mode, events come from the connector (internal network) — no signing needed
      # Check if request is from internal Docker network (connector)
      remote_ip = request.remote_ip.to_s
      return true if remote_ip.start_with?("172.") || remote_ip == "127.0.0.1" || remote_ip == "::1"

      # External requests need signing secret verification
      signing_secret = VaultEntry.find_by(namespace: "channel_credentials", key: "slack_webhook_secret")&.value
      return true unless signing_secret

      timestamp = request.headers["X-Slack-Request-Timestamp"]
      signature = request.headers["X-Slack-Signature"]
      return false unless timestamp && signature

      return false if (Time.now.to_i - timestamp.to_i).abs > 300

      sig_basestring = "v0:#{timestamp}:#{request.raw_post}"
      expected = "v0=#{OpenSSL::HMAC.hexdigest("SHA256", signing_secret, sig_basestring)}"
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end

    private

    def resolve_bot_token(agent = nil)
      # Try agent-specific token first if agent provided
      if agent
        agent_channel = channel.agent_channels.find_by(agent: agent)
        if agent_channel&.has_bot_token?
          return agent_channel.bot_token
        end
      end

      # Fall back to channel-level bot token
      bot_token
    end

    def bot_token
      VaultEntry.find_by(namespace: "channel_credentials", key: "slack_bot_token")&.value
    end

    def slack_post(method, body, token)
      uri = URI("#{BASE_URL}/#{method}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 15

      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Content-Type"] = "application/json"
      req.body = body.to_json

      JSON.parse(http.request(req).body)
    rescue StandardError => e
      { "ok" => false, "error" => e.message }
    end
  end
end
