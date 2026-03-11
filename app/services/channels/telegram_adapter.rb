# frozen_string_literal: true

require "net/http"
require "json"

module Channels
  class TelegramAdapter < BaseAdapter
    BASE_URL = "https://api.telegram.org"

    def receive(message)
      payload = message.deep_symbolize_keys
      msg = payload[:message] || payload[:edited_message]
      return ServiceResponse.success(data: { skipped: true }) unless msg

      content = msg[:text] || msg[:caption] || ""
      metadata = {
        chat_id: msg.dig(:chat, :id),
        chat_type: msg.dig(:chat, :type),
        from: msg[:from],
        date: msg[:date],
        reply_to_message_id: msg.dig(:reply_to_message, :message_id)
      }

      if msg[:photo].present?
        largest_photo = msg[:photo].max_by { |p| p[:file_size].to_i }
        metadata[:photo_file_id] = largest_photo[:file_id]
        metadata[:has_photo] = true
      end

      inbound = log_inbound_message(
        external_id: msg[:message_id].to_s,
        sender: msg.dig(:from, :id).to_s,
        content: content,
        metadata: metadata
      )

      ServiceResponse.success(data: { inbound_message: inbound })
    rescue StandardError => e
      ServiceResponse.failure(error: "Telegram receive failed: #{e.message}")
    end

    def send_message(to:, content:, **options)
      token = bot_token
      return ServiceResponse.failure(error: "Telegram bot token not configured") unless token

      if options[:photo_url].present? || options[:photo_file_id].present?
        return send_photo(to: to, token: token, content: content, **options)
      end

      uri = URI("#{BASE_URL}/bot#{token}/sendMessage")
      body = {
        chat_id: to,
        text: content,
        parse_mode: options[:parse_mode] || "Markdown"
      }
      body[:reply_to_message_id] = options[:reply_to] if options[:reply_to]
      body[:disable_notification] = true if options[:silent]

      response = post_json(uri, body)

      if response["ok"]
        outbound = log_outbound_message(
          recipient: to,
          content: content,
          metadata: { message_id: response.dig("result", "message_id") }
        )
        ServiceResponse.success(data: { outbound_message: outbound, response: response["result"] })
      else
        ServiceResponse.failure(error: "Telegram API: #{response["description"]}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Telegram send failed: #{e.message}")
    end

    def react(message_id:, emoji:, chat_id: nil)
      token = bot_token
      return ServiceResponse.failure(error: "Bot token not configured") unless token

      target_chat = chat_id || channel.config&.dig("default_chat_id")
      return ServiceResponse.failure(error: "No chat_id for reaction") unless target_chat

      uri = URI("#{BASE_URL}/bot#{token}/setMessageReaction")
      body = {
        chat_id: target_chat,
        message_id: message_id,
        reaction: [ { type: "emoji", emoji: emoji } ]
      }

      response = post_json(uri, body)
      response["ok"] ? ServiceResponse.success(data: {}) : ServiceResponse.failure(error: response["description"])
    end

    def verify_webhook(request)
      secret = channel.config&.dig("webhook_secret")
      return true unless secret

      request.headers["X-Telegram-Bot-Api-Secret-Token"] == secret
    end

    private

    def bot_token
      entry = VaultEntry.find_by(namespace: "channel_credentials", key: "telegram_bot_token")
      entry&.value
    end

    def send_photo(to:, token:, content:, **options)
      uri = URI("#{BASE_URL}/bot#{token}/sendPhoto")
      body = { chat_id: to }
      body[:photo] = options[:photo_url] || options[:photo_file_id]
      body[:caption] = content if content.present?
      body[:parse_mode] = options[:parse_mode] || "Markdown"
      body[:reply_to_message_id] = options[:reply_to] if options[:reply_to]

      response = post_json(uri, body)

      if response["ok"]
        outbound = log_outbound_message(
          recipient: to,
          content: content,
          metadata: { message_id: response.dig("result", "message_id"), type: "photo" }
        )
        ServiceResponse.success(data: { outbound_message: outbound, response: response["result"] })
      else
        ServiceResponse.failure(error: "Telegram API: #{response["description"]}")
      end
    end

    def post_json(uri, body)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 15

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body = body.to_json

      JSON.parse(http.request(req).body)
    rescue StandardError => e
      { "ok" => false, "description" => e.message }
    end
  end
end
