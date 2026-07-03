# frozen_string_literal: true

require "net/http"
require "json"

module Channels
  class SignalAdapter < BaseAdapter
    # Connects to signal-cli REST API (typically running as a sidecar)
    # Default: http://signal-cli:8080 (Docker) or configurable

    def receive(message)
      payload = message.deep_symbolize_keys
      envelope = payload[:envelope] || payload
      data_msg = envelope[:dataMessage]
      return ServiceResponse.success(data: { skipped: true }) unless data_msg

      metadata = {
        source_name: envelope[:sourceName],
        group_id: data_msg.dig(:groupInfo, :groupId),
        timestamp: data_msg[:timestamp],
        quote: data_msg[:quote]
      }

      if data_msg[:attachments].present?
        metadata[:attachments] = data_msg[:attachments].map do |att|
          { content_type: att[:contentType], filename: att[:filename], size: att[:size] }
        end
      end

      inbound = log_inbound_message(
        external_id: data_msg[:timestamp].to_s,
        sender: envelope[:source].to_s,
        content: data_msg[:message].to_s,
        metadata: metadata
      )

      ServiceResponse.success(data: { inbound_message: inbound })
    rescue StandardError => e
      ServiceResponse.failure(error: "Signal receive failed: #{e.message}")
    end

    def send_message(to:, content:, **options)
      base = signal_api_url
      number = registered_number
      return ServiceResponse.failure(error: "Signal not configured (need API URL + registered number)") unless base && number

      uri = URI("#{base}/v2/send")
      body = {
        message: content,
        number: number,
        recipients: [ to ]
      }

      if options[:quote_timestamp] && options[:quote_author]
        body[:quote_timestamp] = options[:quote_timestamp]
        body[:quote_author] = options[:quote_author]
      end

      response = signal_post(uri, body)

      if response.is_a?(Net::HTTPSuccess)
        outbound = log_outbound_message(recipient: to, content: content)
        ServiceResponse.success(data: { outbound_message: outbound })
      else
        ServiceResponse.failure(error: "Signal API error: #{response.code} #{response.body&.truncate(200)}")
      end
    rescue Errno::ECONNREFUSED
      ServiceResponse.failure(error: "Signal CLI not running at #{signal_api_url}")
    rescue StandardError => e
      ServiceResponse.failure(error: "Signal send failed: #{e.message}")
    end

    def verify_webhook(request)
      secret = channel.config&.dig("webhook_secret")
      unless secret
        # ponytail: no secret = warn+allow for backwards compat; enforce by setting webhook_secret on the channel
        Rails.logger.warn("[signal] webhook_secret not configured — accepting unauthenticated request from #{request.remote_ip}")
        return true
      end

      token = request.headers["X-Signal-Webhook-Token"].to_s
      ActiveSupport::SecurityUtils.secure_compare(token, secret)
    end

    private

    def signal_api_url
      channel.config&.dig("api_url") || "http://signal-cli:8080"
    end

    def registered_number
      channel.config&.dig("phone_number")
    end

    def signal_post(uri, body)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 15

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body = body.to_json

      http.request(req)
    end
  end
end
