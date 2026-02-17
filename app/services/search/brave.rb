# frozen_string_literal: true

module Search
  class Brave < Base
    API_URL = "https://api.search.brave.com/res/v1/web/search"

    def search(query, count: 5, country: nil, language: nil)
      params = { q: query, count: count }
      params[:country] = country if country.present?
      params[:search_lang] = language if language.present?

      uri = URI(API_URL)
      uri.query = URI.encode_www_form(params)

      data = http_get(uri, {
        "Accept" => "application/json",
        "Accept-Encoding" => "gzip",
        "X-Subscription-Token" => @api_key
      })

      (data.dig("web", "results") || []).first(count).map do |r|
        Result.new(title: r["title"], url: r["url"], snippet: r["description"])
      end
    end
  end
end
