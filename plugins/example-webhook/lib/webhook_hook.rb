# frozen_string_literal: true

module ExampleWebhook
  class AfterChatHook
    def call(payload)
      webhook_url = ENV["EXAMPLE_WEBHOOK_URL"]
      return ServiceResponse.success(data: { skipped: true }) unless webhook_url.present?

      uri = URI(webhook_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = {
        event: "after_chat",
        agent: payload[:agent]&.name,
        session_id: payload[:session_id],
        timestamp: Time.current.iso8601
      }.to_json

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        ServiceResponse.success(data: { status: response.code })
      else
        ServiceResponse.failure(error: "Webhook returned #{response.code}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Webhook error: #{e.message}")
    end
  end
end
