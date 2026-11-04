# frozen_string_literal: true

require "faraday"
require "json"
require "securerandom"
require "digest"
require "ipaddr"

module Mcp
  # OAuth 2.1 client for remote MCP servers, following the MCP authorization
  # spec: protected resource metadata (RFC 9728), authorization server metadata
  # (RFC 8414 / OIDC discovery), dynamic client registration (RFC 7591), PKCE
  # S256, resource indicators (RFC 8707) and refresh tokens.
  #
  # Everything secret (client credentials, tokens, the pending PKCE verifier)
  # lives in VaultEntry rows under the namespace +mcp_oauth_<server id>+.
  class OAuth
    class Error < StandardError; end

    STATE_TTL = 10.minutes
    EXPIRY_SKEW = 30.seconds
    TIMEOUT = 15
    CLIENT_NAME = "Hivemind"

    # Starts the flow for +server+ and returns the URL to send the browser to.
    def self.authorization_url(server, redirect_uri:)
      new(server).authorization_url(redirect_uri: redirect_uri)
    end

    # Finishes the flow: validates +state+, swaps +code+ for tokens and stores them.
    def self.complete!(server, code:, state:)
      new(server).complete!(code: code, state: state)
    end

    # Request headers carrying a current bearer token, or {} when the server has none.
    def self.headers_for(server)
      new(server).headers
    end

    def self.refresh!(server)
      new(server).refresh!
    end

    def self.connected?(server)
      new(server).tokens.present?
    end

    def self.refreshable?(server)
      new(server).tokens["refresh_token"].present?
    end

    def initialize(server)
      @server = server
    end

    def authorization_url(redirect_uri:)
      info = discover
      client = client_for(info, redirect_uri)
      verifier = SecureRandom.urlsafe_base64(48)
      state = SecureRandom.urlsafe_base64(32)
      write(:pending, { "state" => state, "verifier" => verifier, "redirect_uri" => redirect_uri,
                        "expires_at" => STATE_TTL.from_now.to_i })
      query = { response_type: "code", client_id: client["client_id"], redirect_uri: redirect_uri,
                code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false),
                code_challenge_method: "S256", state: state, resource: resource }
      query[:scope] = info["scope"] if info["scope"].present?
      join_query(info["as"]["authorization_endpoint"], query)
    end

    def complete!(code:, state:)
      pending = read(:pending)
      delete(:pending)
      raise Error, "No authorization is pending for this server" if pending.blank?
      raise Error, "Authorization expired, try again" if Time.current.to_i > pending["expires_at"].to_i
      raise Error, "Invalid state" unless state.present? && ActiveSupport::SecurityUtils.secure_compare(state.to_s, pending["state"].to_s)

      store_tokens(token_request(read(:client), grant_type: "authorization_code", code: code,
                                                redirect_uri: pending["redirect_uri"], code_verifier: pending["verifier"]))
    end

    def headers
      refresh! if expired?
      token = tokens["access_token"]
      token.present? ? { "Authorization" => "Bearer #{token}" } : {}
    end

    def refresh!
      refresh_token = tokens["refresh_token"]
      raise Error, "No refresh token, reconnect the server" if refresh_token.blank?

      store_tokens(token_request(read(:client), grant_type: "refresh_token", refresh_token: refresh_token),
                   previous_refresh: refresh_token)
    end

    def tokens
      read(:tokens)
    end

    private

    def expired?
      expires_at = tokens["expires_at"]
      expires_at.present? && tokens["refresh_token"].present? && Time.current.to_i >= expires_at.to_i - EXPIRY_SKEW.to_i
    end

    def resource
      @server.url.to_s.sub(/#.*\z/, "")
    end

    # Probes the server for a 401, follows its resource metadata to the
    # authorization server and returns {"as" => metadata, "scope" => ...}.
    def discover
      challenge = probe_challenge
      prm = fetch_json(challenge[:resource_metadata]) if challenge[:resource_metadata]
      prm ||= well_known_candidates(resource, "oauth-protected-resource").lazy.filter_map { |u| fetch_json(u) }.first
      issuer = prm&.dig("authorization_servers")&.first || origin(resource)
      candidates = well_known_candidates(issuer, "oauth-authorization-server") + [ "#{issuer.chomp('/')}/.well-known/openid-configuration" ]
      as = candidates.lazy.filter_map { |u| fetch_json(u) }.first
      raise Error, "Could not find authorization server metadata for #{issuer}" unless as&.dig("authorization_endpoint") && as["token_endpoint"]
      unless %w[authorization_endpoint token_endpoint].all? { |k| secure_url?(as[k]) }
        raise Error, "Authorization server endpoints must use https"
      end

      { "as" => as, "scope" => challenge[:scope] || prm&.dig("scopes_supported")&.join(" ") }
    end

    def probe_challenge
      response = Faraday.new(request: { timeout: TIMEOUT }).post(resource) do |req|
        req.headers = { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream" }
        req.body = { jsonrpc: "2.0", id: 1, method: "initialize",
                     params: { protocolVersion: Mcp::HttpClient::PROTOCOL_VERSION, capabilities: {},
                               clientInfo: { name: "hivemind", version: "1.0" } } }.to_json
      end
      header = response.headers["WWW-Authenticate"].to_s
      { resource_metadata: header[/resource_metadata="([^"]+)"/, 1], scope: header[/scope="([^"]+)"/, 1] }
    rescue Faraday::Error => e
      raise Error, "Could not reach #{resource}: #{e.message}"
    end

    # Well-known URLs for +base+, with the path inserted after the host (RFC 8414 / RFC 9728).
    def well_known_candidates(base, suffix)
      path = URI.parse(base).path.to_s.chomp("/")
      urls = [ "#{origin(base)}/.well-known/#{suffix}#{path}" ]
      urls << "#{origin(base)}/.well-known/#{suffix}" if path.present?
      urls
    end

    def origin(url)
      uri = URI.parse(url)
      "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.port == uri.default_port}"
    end

    def fetch_json(url)
      return unless secure_url?(url)

      response = Faraday.new(request: { timeout: TIMEOUT }).get(url)
      response.success? ? JSON.parse(response.body) : nil
    rescue Faraday::Error, JSON::ParserError
      nil
    end

    # https everywhere, plus http for loopback, LAN and .local hosts.
    def secure_url?(url)
      uri = URI.parse(url.to_s)
      return true if uri.scheme == "https"
      return false unless uri.scheme == "http" && uri.host.present?

      host = uri.host
      return true if host == "localhost" || host.end_with?(".local") || !host.include?(".")

      ip = IPAddr.new(host)
      ip.loopback? || ip.private? || ip.link_local?
    rescue IPAddr::InvalidAddressError, URI::InvalidURIError
      false
    end

    def client_for(info, redirect_uri)
      client = read(:client)
      issuer = info["as"]["issuer"].presence || info["as"]["token_endpoint"]
      if @server.oauth_client_id
        client = manual_client.merge("redirect_uri" => redirect_uri, "issuer" => issuer)
      elsif client.blank? || client["redirect_uri"] != redirect_uri || client["issuer"] != issuer
        client = register(info["as"], redirect_uri).merge("redirect_uri" => redirect_uri, "issuer" => issuer)
      end
      client = client.merge("token_endpoint" => info["as"]["token_endpoint"])
      write(:client, client)
      client
    end

    # The client id and secret entered on the server form, used instead of registering.
    def manual_client
      { "client_id" => @server.oauth_client_id, "client_secret" => @server.oauth_client_secret.presence }.compact
    end

    def register(as, redirect_uri)
      endpoint = as["registration_endpoint"]
      raise Error, "Server does not support dynamic client registration" if endpoint.blank? || !secure_url?(endpoint)

      response = Faraday.new(request: { timeout: TIMEOUT }).post(endpoint) do |req|
        req.headers = { "Content-Type" => "application/json", "Accept" => "application/json" }
        req.body = { client_name: CLIENT_NAME, redirect_uris: [ redirect_uri ], grant_types: %w[authorization_code refresh_token],
                     response_types: [ "code" ], token_endpoint_auth_method: "none" }.to_json
      end
      raise Error, "Client registration failed (HTTP #{response.status})" unless response.success?

      body = JSON.parse(response.body)
      raise Error, "Client registration returned no client_id" if body["client_id"].blank?

      body.slice("client_id", "client_secret")
    rescue Faraday::Error, JSON::ParserError => e
      raise Error, "Client registration failed: #{e.message}"
    end

    def token_request(client, params)
      raise Error, "No client registered for this server" if client.blank?

      form = params.merge(client_id: client["client_id"], resource: resource)
      form[:client_secret] = client["client_secret"] if client["client_secret"].present?
      response = Faraday.new(request: { timeout: TIMEOUT }).post(client["token_endpoint"], form)
      raise Error, "Token request failed (HTTP #{response.status})" unless response.success?

      body = JSON.parse(response.body)
      raise Error, "Token response had no access_token" if body["access_token"].blank?

      body
    rescue Faraday::Error, JSON::ParserError => e
      raise Error, "Token request failed: #{e.message}"
    end

    def store_tokens(body, previous_refresh: nil)
      expires_at = body["expires_in"].present? ? Time.current.to_i + body["expires_in"].to_i : nil
      write(:tokens, { "access_token" => body["access_token"], "refresh_token" => body["refresh_token"].presence || previous_refresh,
                       "expires_at" => expires_at })
    end

    def join_query(endpoint, query)
      uri = URI.parse(endpoint)
      uri.query = [ uri.query.presence, URI.encode_www_form(query) ].compact.join("&")
      uri.to_s
    end

    def namespace
      "mcp_oauth_#{@server.id}"
    end

    def entry(name)
      VaultEntry.find_by(namespace: namespace, key: name.to_s, agent_id: nil)
    end

    def read(name)
      raw = entry(name)&.value
      raw.present? ? JSON.parse(raw) : {}
    rescue JSON::ParserError
      {}
    end

    def write(name, hash)
      record = VaultEntry.find_or_initialize_by(namespace: namespace, key: name.to_s, agent_id: nil)
      record.value = hash.to_json
      record.save!
    end

    def delete(name)
      entry(name)&.destroy
    end
  end
end
