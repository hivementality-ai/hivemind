# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Tools
  class ComposioExecutor < BaseExecutor
    # Composio tool platform (https://composio.dev) — 250+ app integrations.
    #
    # Credentials in vault:
    #   composio/api_key  — Composio API key (app.composio.dev settings)
    #   composio/base_url — optional API base override (defaults to v3)
    #
    # ponytail: thin authenticated proxy — we forward to Composio's REST API and return the JSON
    # verbatim rather than modeling every response shape, so we stay resilient to Composio's frequent
    # API changes. The `request` action is a raw escape hatch if a named path drifts. Bump base_url in
    # vault if Composio moves the version prefix.
    DEFAULT_BASE_URL = "https://backend.composio.dev/api/v3"

    METHODS = {
      "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post, "PUT" => Net::HTTP::Put,
      "PATCH" => Net::HTTP::Patch, "DELETE" => Net::HTTP::Delete
    }.freeze

    def call
      return ServiceResponse.failure(error: "Composio API key not configured") if api_key.blank?

      case input["action"].to_s.strip.presence || "execute"
      when "execute"          then execute_tool
      when "list_tools"       then list_tools
      when "list_toolkits"    then request("GET", "/toolkits")
      when "list_connections" then request("GET", "/connected_accounts")
      when "request"          then raw_request
      else
        ServiceResponse.failure(error: "Unknown action: #{input['action']}. Supported: execute, list_tools, list_toolkits, list_connections, request")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Composio error: #{e.message}")
    end

    private

    def execute_tool
      slug = input["tool_slug"].to_s.strip
      return ServiceResponse.failure(error: "tool_slug is required for execute") if slug.blank?

      body = { arguments: input["arguments"] || {} }
      body[:user_id] = input["user_id"] if input["user_id"].present?
      body[:connected_account_id] = input["connected_account_id"] if input["connected_account_id"].present?
      request("POST", "/tools/execute/#{slug}", body: body)
    end

    def list_tools
      query = {}
      query["toolkit_slug"] = input["toolkit"] if input["toolkit"].present?
      query["limit"] = input["limit"] if input["limit"].present?
      request("GET", "/tools", query: query)
    end

    def raw_request
      path = input["path"].to_s.strip
      return ServiceResponse.failure(error: "path is required for request") if path.blank?

      request((input["method"].presence || "GET").to_s.upcase, path, body: input["body"], query: input["query"])
    end

    def request(method, path, body: nil, query: nil)
      klass = METHODS[method] or return ServiceResponse.failure(error: "Unsupported method: #{method}")

      uri = URI("#{base_url}#{path.start_with?('/') ? path : "/#{path}"}")
      uri.query = URI.encode_www_form(query) if query.is_a?(Hash) && query.any?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 30

      req = klass.new(uri)
      req["x-api-key"] = api_key
      req["Accept"] = "application/json"
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

    def base_url
      @base_url ||= (vault_get("composio", "base_url").presence || ENV["COMPOSIO_BASE_URL"].presence || DEFAULT_BASE_URL).to_s.chomp("/")
    end

    def api_key
      @api_key ||= vault_get("composio", "api_key") || ENV["COMPOSIO_API_KEY"]
    end

    def vault_get(namespace, key)
      VaultEntry.find_by(namespace: namespace, key: key)&.value
    end
  end
end
