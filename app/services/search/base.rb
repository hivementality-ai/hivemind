# frozen_string_literal: true

module Search
  class Base
    Result = Data.define(:title, :url, :snippet)

    def initialize(api_key)
      @api_key = api_key
    end

    def search(query, count: 5, country: nil, language: nil)
      raise NotImplementedError
    end

    private

    def http_get(uri, headers = {})
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 10

      request = Net::HTTP::Get.new(uri)
      headers.each { |k, v| request[k] = v }

      response = http.request(request)
      raise "HTTP #{response.code}: #{response.body.truncate(200)}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
  end
end
