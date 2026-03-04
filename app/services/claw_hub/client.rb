# frozen_string_literal: true

module ClawHub
  class ApiError < StandardError
    attr_reader :status

    def initialize(message, status: nil)
      @status = status
      super(message)
    end
  end

  class Client
    BASE_URL = "https://clawhub.ai"

    def initialize
      @conn = Faraday.new(url: BASE_URL) do |f|
        f.request :json
        f.response :json, content_type: /\bjson$/
        f.options.open_timeout = 10
        f.options.timeout = 30
        f.headers["User-Agent"] = "Hivemind/1.0"
      end
    end

    def list_skills(limit: 20, cursor: nil, sort: "trending")
      params = { limit: limit, sort: sort }
      params[:cursor] = cursor if cursor
      get("/api/v1/skills", params)
    end

    def search_skills(query:, limit: 20)
      get("/api/v1/search", q: query, limit: limit)
    end

    def get_skill(slug:)
      get("/api/v1/skills/#{slug}")
    end

    def get_skill_file(slug:, path:, version: nil)
      params = { path: path }
      params[:version] = version if version
      response = @conn.get("/api/v1/skills/#{slug}/file", params)
      raise ApiError.new("ClawHub API error: #{response.status}", status: response.status) unless response.success?

      response.body
    end

    def download_zip(slug:, version: nil)
      params = { slug: slug }
      params[:version] = version if version
      response = @conn.get("/api/v1/download", params)
      raise ApiError.new("ClawHub API error: #{response.status}", status: response.status) unless response.success?

      response.body
    end

    private

    def get(path, params = {})
      response = @conn.get(path, params)
      raise ApiError.new("ClawHub API error: #{response.status}", status: response.status) unless response.success?

      response.body
    end
  end
end
