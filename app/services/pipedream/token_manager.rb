# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Pipedream
  # Manages Pipedream Connect credentials for the install.
  #
  # Config (set via the Integrations page):
  #   VaultEntry pipedream/client_id, pipedream/client_secret
  #   Setting    pipedream_project_id, pipedream_environment, pipedream_external_user_id
  #
  # Two tokens:
  #   access_token       — OAuth client_credentials token used to auth MCP + REST calls (~1h TTL, cached ~55m)
  #   mint_connect_token — short-lived Connect token + hosted Connect Link URL for the end user to
  #                        authorize an app account (Slack, Gmail, ...)
  class TokenManager
    OAUTH_TOKEN_URL = "https://api.pipedream.com/v1/oauth/token"
    API_BASE_URL = "https://api.pipedream.com/v1"
    VAULT_NAMESPACE = "pipedream"
    ACCESS_TOKEN_CACHE_KEY = "pipedream:access_token"
    ACCESS_TOKEN_TTL = 55.minutes
    HTTP_TIMEOUT = 10

    attr_reader :project_id, :environment

    def initialize
      @client_id = VaultEntry.find_by(namespace: VAULT_NAMESPACE, key: "client_id")&.value
      @client_secret = VaultEntry.find_by(namespace: VAULT_NAMESPACE, key: "client_secret")&.value
      @project_id = Setting.get("pipedream_project_id")
      @environment = Setting.get("pipedream_environment") || "development"
    end

    def configured?
      @client_id.present? && @client_secret.present? && @project_id.present?
    end

    def access_token
      return nil unless configured?

      cached = Rails.cache.read(ACCESS_TOKEN_CACHE_KEY)
      return cached if cached.present?

      token = fetch_access_token
      return nil unless token

      Rails.cache.write(ACCESS_TOKEN_CACHE_KEY, token, expires_in: ACCESS_TOKEN_TTL)
      token
    end

    def refresh_access_token!
      Rails.cache.delete(ACCESS_TOKEN_CACHE_KEY)
      access_token
    end

    # Mints a Connect token and returns the hosted Connect Link URL the end user visits to
    # authorize their app account. Docs: POST /connect/{project_id}/tokens
    def mint_connect_token(external_user_id:, success_redirect_uri:, error_redirect_uri: nil, app_slug: nil)
      return ServiceResponse.failure(error: "Not configured") unless configured?

      token = access_token
      return ServiceResponse.failure(error: "Could not obtain Pipedream access token") unless token

      body = { external_user_id: external_user_id, success_redirect_uri: success_redirect_uri }
      body[:error_redirect_uri] = error_redirect_uri if error_redirect_uri.present?

      response = post_json(
        "#{API_BASE_URL}/connect/#{@project_id}/tokens",
        body,
        "Authorization" => "Bearer #{token}",
        "x-pd-environment" => @environment
      )
      data = JSON.parse(response.body)

      if response.is_a?(Net::HTTPSuccess) && data["connect_link_url"].present?
        ServiceResponse.success(data: {
          token: data["token"],
          expires_at: data["expires_at"],
          connect_url: append_app(data["connect_link_url"], app_slug)
        })
      else
        ServiceResponse.failure(error: data["error"] || data["message"] || "Connect token request failed")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Connect token mint failed: #{e.message}")
    end

    private

    def fetch_access_token
      response = post_json(OAUTH_TOKEN_URL, {
        grant_type: "client_credentials",
        client_id: @client_id,
        client_secret: @client_secret
      })
      return nil unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)["access_token"]
    rescue StandardError
      nil
    end

    def post_json(url, body, extra_headers = {})
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = HTTP_TIMEOUT
      http.read_timeout = HTTP_TIMEOUT

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      extra_headers.each { |k, v| req[k] = v }
      req.body = body.to_json
      http.request(req)
    end

    def append_app(url, app_slug)
      return url if app_slug.blank?

      sep = url.include?("?") ? "&" : "?"
      "#{url}#{sep}app=#{URI.encode_www_form_component(app_slug)}"
    end
  end
end
