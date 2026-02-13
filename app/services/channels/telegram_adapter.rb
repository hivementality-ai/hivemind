# frozen_string_literal: true

module Channels
  class TelegramAdapter < BaseAdapter
    BASE_URL = "https://api.telegram.org"

    def receive(message)
      # Parse Telegram update
      update = message.deep_symbolize_keys
      
      return ServiceResponse.success(data: { skipped: true }) unless update[:message]

      telegram_message = update[:message]
      
      # Log the inbound message
      inbound = log_inbound_message(
        external_id: telegram_message[:message_id].to_s,
        sender: telegram_message.dig(:from, :id).to_s,
        content: telegram_message[:text] || telegram_message[:caption] || "",
        metadata: {
          chat_id: telegram_message.dig(:chat, :id),
          from: telegram_message[:from],
          date: telegram_message[:date]
        }
      )

      # Process the message (route to appropriate agent)
      # This would be handled by a separate service in production
      
      ServiceResponse.success(data: { inbound_message: inbound })
    rescue StandardError => e
      ServiceResponse.failure(error: "Telegram receive failed: #{e.message}")
    end

    def send_message(to:, content:, **options)
      bot_token = get_bot_token
      return ServiceResponse.failure(error: "Bot token not configured") unless bot_token

      payload = {
        chat_id: to,
        text: content,
        parse_mode: options[:parse_mode] || "Markdown"
      }

      response = Faraday.post(
        "#{BASE_URL}/bot#{bot_token}/sendMessage",
        payload.to_json,
        { "Content-Type" => "application/json" }
      )

      if response.success?
        result = JSON.parse(response.body)
        
        # Log outbound message
        outbound = log_outbound_message(
          recipient: to,
          content: content,
          metadata: { 
            message_id: result.dig("result", "message_id"),
            response: result
          }
        )

        ServiceResponse.success(data: { outbound_message: outbound, response: result })
      else
        ServiceResponse.failure(error: "Telegram API error: #{response.body}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Telegram send failed: #{e.message}")
    end

    def verify_webhook(request)
      # Telegram uses a secret token for webhook verification
      token = request.headers["X-Telegram-Bot-Api-Secret-Token"]
      secret = webhook_secret

      return false unless secret && token

      ActiveSupport::SecurityUtils.secure_compare(secret, token)
    end

    private

    def get_bot_token
      vault_entry = VaultEntry.find_by(
        namespace: "channel_credentials",
        key: "telegram_bot_token"
      )
      vault_entry&.encrypted_value
    end
  end
end
