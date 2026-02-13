# frozen_string_literal: true

module Channels
  class DiscordAdapter < BaseAdapter
    BASE_URL = "https://discord.com/api/v10"

    def receive(message)
      # Parse Discord interaction or message
      payload = message.deep_symbolize_keys
      
      # Discord uses different structures for gateway events vs webhook interactions
      # This is a simplified version
      
      if payload[:content].present?
        inbound = log_inbound_message(
          external_id: payload[:id].to_s,
          sender: payload.dig(:author, :id).to_s,
          content: payload[:content],
          metadata: {
            channel_id: payload[:channel_id],
            guild_id: payload[:guild_id],
            author: payload[:author]
          }
        )

        ServiceResponse.success(data: { inbound_message: inbound })
      else
        ServiceResponse.success(data: { skipped: true })
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Discord receive failed: #{e.message}")
    end

    def send_message(to:, content:, **options)
      bot_token = get_bot_token
      return ServiceResponse.failure(error: "Bot token not configured") unless bot_token

      payload = {
        content: content
      }

      payload[:embeds] = options[:embeds] if options[:embeds]

      response = Faraday.post(
        "#{BASE_URL}/channels/#{to}/messages",
        payload.to_json,
        {
          "Authorization" => "Bot #{bot_token}",
          "Content-Type" => "application/json"
        }
      )

      if response.success?
        result = JSON.parse(response.body)
        
        outbound = log_outbound_message(
          recipient: to,
          content: content,
          metadata: { 
            message_id: result["id"],
            response: result
          }
        )

        ServiceResponse.success(data: { outbound_message: outbound, response: result })
      else
        ServiceResponse.failure(error: "Discord API error: #{response.body}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Discord send failed: #{e.message}")
    end

    def verify_webhook(request)
      # Discord uses Ed25519 signature verification
      signature = request.headers["X-Signature-Ed25519"]
      timestamp = request.headers["X-Signature-Timestamp"]
      
      return false unless signature && timestamp

      public_key = get_public_key
      return false unless public_key

      begin
        verify_key = Ed25519::VerifyKey.new([public_key].pack("H*"))
        verify_key.verify([signature].pack("H*"), timestamp + request.raw_post)
        true
      rescue Ed25519::VerifyError
        false
      end
    end

    private

    def get_bot_token
      vault_entry = VaultEntry.find_by(
        namespace: "channel_credentials",
        key: "discord_bot_token"
      )
      vault_entry&.encrypted_value
    end

    def get_public_key
      vault_entry = VaultEntry.find_by(
        namespace: "channel_credentials",
        key: "discord_public_key"
      )
      vault_entry&.encrypted_value
    end
  end
end
