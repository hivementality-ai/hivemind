# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Tools
  class BrowserExecutor < BaseExecutor
    SIDECAR_URL = ENV.fetch("BROWSER_SIDECAR_URL", "http://browser-sidecar:3004")
    REQUEST_TIMEOUT = 35

    # Supported actions: navigate (default), screenshot
    def call
      action = input["action"].to_s.strip
      url    = input["url"].to_s.strip

      return ServiceResponse.failure(error: "No URL provided") if url.empty?

      case action
      when "navigate", "get", ""
        navigate(url)
      when "screenshot"
        screenshot(url)
      else
        ServiceResponse.failure(error: "Unknown browser action: #{action}. Supported: navigate, screenshot")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Browser error: #{e.message}")
    end

    private

    def navigate(url)
      result = post_to_sidecar("/navigate", { url: url })
      return ServiceResponse.failure(error: result[:error]) unless result[:success]

      lines = []
      lines << "Title: #{result[:title]}" if result[:title].present?
      lines << "URL: #{result[:url]}"     if result[:url].present?
      lines << ""
      lines << result[:content].to_s

      ServiceResponse.success(data: { output: lines.join("\n"), exit_code: 0 })
    end

    def screenshot(url)
      result = post_to_sidecar("/screenshot", { url: url })
      return ServiceResponse.failure(error: result[:error]) unless result[:success]

      ServiceResponse.success(data: {
        output: "Screenshot saved: #{result[:path]}\nTitle: #{result[:title]}",
        exit_code: 0
      })
    end

    def post_to_sidecar(path, payload)
      uri = URI("#{SIDECAR_URL}#{path}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 10
      http.read_timeout = REQUEST_TIMEOUT

      request = Net::HTTP::Post.new(uri.path, { "Content-Type" => "application/json" })
      request.body = payload.to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        return { success: false, error: "Browser sidecar error (#{response.code}): #{response.body}" }
      end

      JSON.parse(response.body, symbolize_names: true)
    rescue JSON::ParserError
      { success: false, error: "Invalid response from browser sidecar" }
    end
  end
end
