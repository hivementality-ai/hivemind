# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Tools
  class WebSearchExecutor < BaseExecutor
    def call
      query = input["query"].to_s.strip
      return ServiceResponse.failure(error: "No query provided") if query.empty?

      # Use DuckDuckGo instant answer API (no key required)
      uri = URI.parse("https://api.duckduckgo.com/?q=#{URI.encode_www_form_component(query)}&format=json&no_html=1")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 10

      response = http.request(Net::HTTP::Get.new(uri))
      data = JSON.parse(response.body)

      results = []

      # Abstract
      if data["Abstract"].present?
        results << "## #{data["Heading"]}\n#{data["Abstract"]}\nSource: #{data["AbstractURL"]}"
      end

      # Related topics
      (data["RelatedTopics"] || []).first(5).each do |topic|
        next unless topic["Text"]
        results << "- #{topic["Text"]}"
        results << "  #{topic["FirstURL"]}" if topic["FirstURL"]
      end

      if results.empty?
        results << "No instant results found for '#{query}'. Try web_fetch with a specific URL for more detailed information."
      end

      ServiceResponse.success(data: { output: results.join("\n"), exit_code: 0 })
    rescue StandardError => e
      ServiceResponse.failure(error: "Search failed: #{e.message}")
    end
  end
end
