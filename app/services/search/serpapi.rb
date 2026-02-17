# frozen_string_literal: true

module Search
  class Serpapi < Base
    API_URL = "https://serpapi.com/search"

    def search(query, count: 5, country: nil, language: nil)
      params = { engine: "google", q: query, num: count, api_key: @api_key }
      params[:gl] = country if country.present?
      params[:hl] = language if language.present?

      uri = URI(API_URL)
      uri.query = URI.encode_www_form(params)

      data = http_get(uri)

      (data["organic_results"] || []).first(count).map do |r|
        Result.new(title: r["title"], url: r["link"], snippet: r["snippet"])
      end
    end
  end
end
