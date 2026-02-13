# frozen_string_literal: true

module Channels
  class SlackAdapter < BaseAdapter
    BASE_URL = "https://slack.com/api"

    def receive(message)
      payload = message.deep_symbolize_keys
      
      # Handle Slack challenge for webhook verification
      if payload[:type] == "url_verification"
        return ServiceResponse.success(data: { challenge: payload[:challenge] })
      end

      # Handle regular message events
      if payload[:type] == "event_callback" && payload.dig(:event, :type) == "message"
        event = payload[:event]
        
        # Skip bot messages to avoid loops
        return ServiceResponse.success(data: { skipped: true }) if event[:bot_id].present?

        inbound = log_inbound_message(
          external_id: event[:ts],
          sender: event[:user],
          content: event[:text],
          metadata: {
            channel: event[:channel],
            team: payload[:team_id],
            event_time: event[:event_ts]
          }
        )

        ServiceResponse.success(data: { inbound_message: inbound })
      else
        ServiceResponse.success(data: { skipped: true })
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Slack receive failed: #{e.message}")
    end

    def send_message(to:, content:, **options)
      bot_token = get_bot_token
      return ServiceResponse.failure(error: "Bot token not configured") unless bot_token

      payload = {
        channel: to,
        text: content
      }

      payload[:blocks] = options[:blocks] if options[:blocks]
      payload[:thread_ts] = options[:thread_ts] if options[:thread_ts]

      response = Faraday.post(
        "#{BASE_URL}/chat.postMessage",
        payload.to_json,
        {
          "Authorization" => "Bearer #{bot_token}",
          "Content-Type" => "application/json"
        }
      )

      if response.success?
        result = JSON.parse(response.body)
        
        if result["ok"]
          outbound = log_outbound_message(
            recipient: to,
            content: content,
            metadata: { 
              ts: result["ts"],
              channel: result["channel"]
            }
          )

          ServiceResponse.success(data: { outbound_message: outbound, response: result })
        else
          ServiceResponse.failure(error: "Slack API error: #{result['error']}")
        end
      else
        ServiceResponse.failure(error: "Slack API request failed: #{response.status}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Slack send failed: #{e.message}")
    end

    def verify_webhook(request)
      # Slack uses HMAC-SHA256 signature verification
      signature = request.headers["X-Slack-Signature"]
      timestamp = request.headers["X-Slack-Request-Timestamp"]
      
      return false unless signature && timestamp

      # Reject old requests (replay attack prevention)
      return false if (Time.current.to_i - timestamp.to_i).abs > 60 * 5

      signing_secret = webhook_secret
      return false unless signing_secret

      sig_basestring = "v0:#{timestamp}:#{request.raw_post}"
      expected = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', signing_secret, sig_basestring)}"

      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end

    private

    def get_bot_token
      vault_entry = VaultEntry.find_by(
        namespace: "channel_credentials",
        key: "slack_bot_token"
      )
      vault_entry&.encrypted_value
    end
  end
end
