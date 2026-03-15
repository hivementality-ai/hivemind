# frozen_string_literal: true

module GoogleWorkspace
  class OAuthClient
    TOKEN_URL = "https://oauth2.googleapis.com/token"
    AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
    USERINFO_URL = "https://www.googleapis.com/oauth2/v3/userinfo"

    SCOPES = {
      drive: "https://www.googleapis.com/auth/drive",
      calendar: "https://www.googleapis.com/auth/calendar",
      gmail: "https://www.googleapis.com/auth/gmail.modify"
    }.freeze

    DEFAULT_SCOPES = %i[drive calendar].freeze

    VAULT_NAMESPACE = "google_workspace"

    def initialize
      @client_id = VaultEntry.find_by(namespace: VAULT_NAMESPACE, key: "client_id")&.value
      @client_secret = VaultEntry.find_by(namespace: VAULT_NAMESPACE, key: "client_secret")&.value
    end

    def configured?
      @client_id.present? && @client_secret.present?
    end

    def authorization_url(redirect_uri:, state:, scopes: DEFAULT_SCOPES)
      scope_string = scopes.map { |s| SCOPES[s] || s.to_s }.join(" ")

      params = {
        client_id: @client_id,
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: scope_string,
        access_type: "offline",
        prompt: "consent",
        state: state
      }

      "#{AUTH_URL}?#{URI.encode_www_form(params)}"
    end

    def exchange_code(code:, redirect_uri:)
      uri = URI(TOKEN_URL)
      response = Net::HTTP.post_form(uri, {
        code: code,
        client_id: @client_id,
        client_secret: @client_secret,
        redirect_uri: redirect_uri,
        grant_type: "authorization_code"
      })

      data = JSON.parse(response.body)

      if data["error"]
        ServiceResponse.failure(error: "OAuth error: #{data["error_description"] || data["error"]}")
      else
        ServiceResponse.success(data: {
          access_token: data["access_token"],
          refresh_token: data["refresh_token"],
          expires_in: data["expires_in"],
          scope: data["scope"]
        })
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Token exchange failed: #{e.message}")
    end

    def refresh_token(refresh_token)
      uri = URI(TOKEN_URL)
      response = Net::HTTP.post_form(uri, {
        refresh_token: refresh_token,
        client_id: @client_id,
        client_secret: @client_secret,
        grant_type: "refresh_token"
      })

      data = JSON.parse(response.body)

      if data["error"]
        ServiceResponse.failure(error: "Refresh failed: #{data["error_description"] || data["error"]}")
      else
        ServiceResponse.success(data: {
          access_token: data["access_token"],
          expires_in: data["expires_in"]
        })
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Token refresh failed: #{e.message}")
    end

    def fetch_user_info(access_token)
      uri = URI(USERINFO_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 5

      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{access_token}"

      response = http.request(req)
      data = JSON.parse(response.body)

      if response.is_a?(Net::HTTPSuccess)
        ServiceResponse.success(data: { email: data["email"], name: data["name"] })
      else
        ServiceResponse.failure(error: "Failed to fetch user info")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: e.message)
    end
  end
end
