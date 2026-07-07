# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Tools
  class NangoExecutor < BaseExecutor
    # Nango unified-API proxy (https://docs.nango.dev).
    #
    # Credentials in vault:
    #   nango/secret_key — Nango secret key (Environment Settings page)
    #   nango/host       — optional self-hosted base URL (defaults to https://api.nango.dev)
    #
    # Nango injects the OAuth token for a connected account, so agents can call any connected
    # provider's API without ever touching credentials.
    DEFAULT_HOST = "https://api.nango.dev"

    METHODS = {
      "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post, "PUT" => Net::HTTP::Put,
      "PATCH" => Net::HTTP::Patch, "DELETE" => Net::HTTP::Delete
    }.freeze

    def call
      return ServiceResponse.failure(error: "Nango secret key not configured") if secret_key.blank?

      case input["action"].to_s.strip.presence || "proxy"
      when "proxy"            then proxy
      when "list_connections" then request("GET", "/connection")
      when "list_integrations" then request("GET", "/config")
      else
        ServiceResponse.failure(error: "Unknown action: #{input['action']}. Supported: proxy, list_connections, list_integrations")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Nango error: #{e.message}")
    end

    private

    def proxy
      endpoint = input["endpoint"].to_s.strip
      connection_id = input["connection_id"].to_s.strip
      provider_config_key = input["provider_config_key"].to_s.strip
      if endpoint.blank? || connection_id.blank? || provider_config_key.blank?
        return ServiceResponse.failure(error: "endpoint, connection_id, and provider_config_key are required for proxy")
      end

      headers = { "Connection-Id" => connection_id, "Provider-Config-Key" => provider_config_key }
      headers["Base-Url-Override"] = input["base_url_override"] if input["base_url_override"].present?

      request(
        (input["method"].presence || "GET").to_s.upcase,
        "/proxy/#{endpoint.delete_prefix('/')}",
        body: input["data"], query: input["query"], extra_headers: headers
      )
    end

    def request(method, path, body: nil, query: nil, extra_headers: {})
      klass = METHODS[method] or return ServiceResponse.failure(error: "Unsupported method: #{method}")

      uri = URI("#{host}#{path}")
      uri.query = URI.encode_www_form(query) if query.is_a?(Hash) && query.any?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 30

      req = klass.new(uri)
      req["Authorization"] = "Bearer #{secret_key}"
      req["Accept"] = "application/json"
      extra_headers.each { |k, v| req[k] = v }
      if body.present?
        req["Content-Type"] = "application/json"
        req.body = body.is_a?(String) ? body : body.to_json
      end

      response = http.request(req)
      output = response.body.to_s
      if response.is_a?(Net::HTTPSuccess)
        ServiceResponse.success(data: { output: pretty(output), exit_code: 0 })
      else
        ServiceResponse.failure(error: "HTTP #{response.code}: #{output.truncate(500)}")
      end
    end

    def pretty(body)
      JSON.pretty_generate(JSON.parse(body))
    rescue StandardError
      body
    end

    def host
      @host ||= (vault_get("nango", "host").presence || ENV["NANGO_HOST"].presence || DEFAULT_HOST).to_s.chomp("/")
    end

    def secret_key
      @secret_key ||= vault_get("nango", "secret_key") || ENV["NANGO_SECRET_KEY"]
    end

    def vault_get(namespace, key)
      VaultEntry.find_by(namespace: namespace, key: key)&.value
    end
  end
end
