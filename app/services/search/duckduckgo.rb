# frozen_string_literal: true

module Search
  class Duckduckgo < Base
    API_URL = "https://api.duckduckgo.com/"

    def initialize
      super(nil)
    end

    def search(query, count: 5, country: nil, language: nil)
      uri = URI(API_URL)
      uri.query = URI.encode_www_form(q: query, format: "json", no_html: 1)

      data = http_get(uri)
      results = []

      if data["Abstract"].present?
        results << Result.new(
          title: data["Heading"],
          url: data["AbstractURL"],
          snippet: data["Abstract"]
        )
      end

      (data["RelatedTopics"] || []).first(count).each do |topic|
        next unless topic["Text"]
        results << Result.new(
          title: topic["Text"].truncate(100),
          url: topic["FirstURL"],
          snippet: topic["Text"]
        )
      end

      results.first(count)
    end
  end
end
