# frozen_string_literal: true

module Integrations
  class ConnectionTester
    PROVIDERS = {
      github: {
        vault: { namespace: "github", keys: { token: "token" } },
        url: "https://api.github.com/user",
        auth: ->(creds) { { "Authorization" => "Bearer #{creds[:token]}", "Accept" => "application/vnd.github+json" } },
        parse: ->(body) { user = JSON.parse(body); { user: user["login"], name: user["name"] } }
      },
      jira: {
        vault: { namespace: "jira", keys: { base_url: "base_url", email: "email", api_token: "api_token" } },
        url: ->(creds) { "#{creds[:base_url]}/rest/api/3/myself" },
        auth: ->(creds) { { "Authorization" => "Basic #{Base64.strict_encode64("#{creds[:email]}:#{creds[:api_token]}")}", "Accept" => "application/json" } },
        parse: ->(body) { user = JSON.parse(body); { user: user["displayName"], email: user["emailAddress"] } }
      },
      trello: {
        vault: { namespace: "trello", keys: { api_key: "api_key", token: "token" } },
        url: ->(creds) { "https://api.trello.com/1/members/me?key=#{creds[:api_key]}&token=#{creds[:token]}" },
        auth: ->(_creds) { {} },
        parse: ->(body) { user = JSON.parse(body); { user: user["fullName"], username: user["username"] } }
      },
      telegram: {
        vault: { namespace: "channel_credentials", keys: { token: "telegram_bot_token" } },
        url: ->(creds) { "https://api.telegram.org/bot#{creds[:token]}/getMe" },
        auth: ->(_creds) { {} },
        parse: ->(body) {
          data = JSON.parse(body)
          if data["ok"]
            bot = data["result"]
            { username: bot["username"], name: bot["first_name"] }
          else
            raise data["description"]
          end
        }
      },
      signal: {
        source: :channel,
        channel_type: "signal",
        url: ->(config) { "#{config.dig("api_url") || "http://signal-cli:8080"}/v1/about" },
        auth: ->(_) { {} },
        parse: ->(body) { info = JSON.parse(body); { version: info["versions"]&.first } }
      }
    }.freeze

    def self.call(provider)
      new(provider).call
    end

    def initialize(provider)
      @provider = provider.to_sym
      @config = PROVIDERS[@provider]
    end

    def call
      return ServiceResponse.failure(error: "Unknown provider: #{@provider}") unless @config

      creds = load_credentials
      return ServiceResponse.failure(error: "#{@provider.to_s.titleize} not configured") unless creds

      url = resolve_url(creds)
      uri = URI(url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 5

      req = Net::HTTP::Get.new(uri)
      @config[:auth].call(creds).each { |k, v| req[k] = v }

      response = http.request(req)

      if response.is_a?(Net::HTTPSuccess)
        result = @config[:parse].call(response.body)
        ServiceResponse.success(data: { status: "connected" }.merge(result))
      else
        ServiceResponse.failure(error: "HTTP #{response.code}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: e.message)
    end

    private

    def load_credentials
      if @config[:source] == :channel
        ch = Channel.find_by(channel_type: @config[:channel_type], enabled: true)
        return nil unless ch
        ch.config
      else
        vault = @config[:vault]
        creds = {}
        vault[:keys].each do |key, vault_key|
          entry = VaultEntry.find_by(namespace: vault[:namespace], key: vault_key)
          return nil unless entry
          creds[key] = entry.value
        end
        creds
      end
    end

    def resolve_url(creds)
      url_config = @config[:url]
      url_config.is_a?(Proc) ? url_config.call(creds) : url_config
    end
  end
end
