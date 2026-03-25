# frozen_string_literal: true

module Providers
  class FetchRemoteModels
    CONFIGS = {
      ollama: {
        default_url: "http://host.docker.internal:11434",
        path: "/api/tags",
        timeout: 3,
        parse: ->(body) {
          data = JSON.parse(body)
          (data["models"] || []).map do |m|
            {
              id: m["name"],
              name: m["name"],
              size: (m["size"].to_f / 1_000_000_000).round(1),
              parameter_size: m.dig("details", "parameter_size"),
              family: m.dig("details", "family")
            }
          end
        }
      },
      openai_compatible: {
        default_url: nil,
        path: "/v1/models",
        timeout: 5,
        parse: ->(body) {
          data = JSON.parse(body)
          (data["data"] || []).map do |m|
            { id: m["id"], name: m["id"] }
          end
        }
      }
    }.freeze

    def self.call(provider, url: nil, api_key: nil)
      new(provider, url:, api_key:).call
    end

    def initialize(provider, url: nil, api_key: nil)
      @provider = provider.to_sym
      @config = CONFIGS[@provider]
      @url = url
      @api_key = api_key
    end

    def call
      return ServiceResponse.failure(error: "Unknown provider: #{@provider}") unless @config

      base_url = @url.presence || @config[:default_url]
      uri = URI.parse("#{base_url}#{@config[:path]}")

      unless uri.is_a?(URI::HTTP) && uri.host.present? && !uri.host.match?(/\A\[?::1?\]?\z/)
        return ServiceResponse.failure(error: "Invalid #{@provider} URL")
      end

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @config[:timeout]
      http.read_timeout = @config[:timeout]

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@api_key}" if @api_key.present?

      response = http.request(request)
      models = @config[:parse].call(response.body).sort_by { |m| m[:name] }

      ServiceResponse.success(data: { status: "connected", models: models })
    rescue StandardError => e
      ServiceResponse.failure(error: e.message)
    end
  end
end
