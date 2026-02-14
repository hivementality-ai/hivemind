# frozen_string_literal: true

require "net/http"
require "uri"

module Tools
  class WebFetchExecutor < BaseExecutor
    MAX_BODY = 50_000
    TIMEOUT = 15

    def call
      url = input["url"].to_s.strip
      return ServiceResponse.failure(error: "No URL provided") if url.empty?

      uri = URI.parse(url)
      return ServiceResponse.failure(error: "Invalid URL") unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Hivemind/1.0"
      request["Accept"] = "text/html, text/plain, application/json"

      response = http.request(request)
      body = response.body.to_s.truncate(MAX_BODY)

      # Strip HTML tags for cleaner output
      if response["content-type"]&.include?("html")
        body = body.gsub(/<script[^>]*>.*?<\/script>/mi, "")
                   .gsub(/<style[^>]*>.*?<\/style>/mi, "")
                   .gsub(/<[^>]+>/, " ")
                   .gsub(/\s+/, " ")
                   .strip
                   .truncate(MAX_BODY)
      end

      ServiceResponse.success(data: {
        output: "HTTP #{response.code}\n\n#{body}",
        exit_code: response.code.to_i < 400 ? 0 : 1
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Fetch failed: #{e.message}")
    end
  end
end
