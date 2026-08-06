# frozen_string_literal: true

require "faraday"
require "json"
require "securerandom"

module Cloudflare
  # Orchestrates the fully-automatable half of the guided Cloudflare Tunnel
  # setup (see hivemind-desktop issue #2 and #10 for the decision record).
  #
  # The admin still has to do three things by hand: create a free Cloudflare
  # account, delegate a domain's nameservers to Cloudflare, and mint an API
  # token via the scoped deep link (`token_deep_link`). Everything past that
  # — creating the remotely-managed tunnel, wiring ingress to hivemind's
  # internal port, creating the DNS record, and fetching the run token — is
  # done here against the Cloudflare API with the admin's own token.
  #
  # Each admin authenticates with their own Cloudflare account/token; hivemind
  # never proxies multiple admins through one shared account (see the ToS
  # discussion in issue #2's resolution).
  class TunnelProvisioner
    API_BASE = "https://api.cloudflare.com/client/v4"
    TOKEN_DEEP_LINK_BASE = "https://dash.cloudflare.com/profile/api-tokens"

    Error = Class.new(StandardError)

    # Deep link that pre-fills the token creation form with the exact scopes
    # this integration needs: Account > Cloudflare Tunnel > Edit,
    # Zone > DNS > Edit. Cloudflare doesn't support fully prefilled custom
    # token templates via URL, so this links to the token creation screen;
    # the wizard copy tells the admin which two permissions to add.
    def self.token_deep_link
      "#{TOKEN_DEEP_LINK_BASE}?permissionGroupKeys=%5B%7B%22key%22%3A%22cloudflare_tunnel_write%22%2C%22type%22%3A%22edit%22%7D%2C%7B%22key%22%3A%22dns_write%22%2C%22type%22%3A%22edit%22%7D%5D"
    end

    def initialize(api_token:, internal_port: 3000)
      @api_token = api_token
      @internal_port = internal_port
    end

    # Full provisioning flow. Returns a ServiceResponse whose data includes
    # everything the caller needs to start the connector and set the
    # canonical host: tunnel_id, tunnel_token, hostname, account_id, zone_id.
    def provision(hostname:)
      hostname = hostname.to_s.strip.downcase
      return ServiceResponse.failure(error: "Hostname is required") if hostname.blank?

      account_id = fetch_account_id
      return ServiceResponse.failure(error: "Could not determine Cloudflare account — check the token's permissions") if account_id.blank?

      zone = fetch_zone_for_hostname(account_id, hostname)
      return ServiceResponse.failure(error: "No Cloudflare zone found for #{hostname} — make sure the domain's nameservers point to Cloudflare") unless zone

      tunnel = create_tunnel(account_id, hostname)
      return ServiceResponse.failure(error: tunnel[:error]) unless tunnel[:ok]

      ingress = configure_ingress(account_id, tunnel[:id], hostname)
      return ServiceResponse.failure(error: ingress[:error]) unless ingress[:ok]

      dns = create_cname(zone["id"], hostname, tunnel[:id])
      return ServiceResponse.failure(error: dns[:error]) unless dns[:ok]

      ServiceResponse.success(data: {
        account_id: account_id,
        zone_id: zone["id"],
        tunnel_id: tunnel[:id],
        tunnel_token: tunnel[:token],
        hostname: hostname,
        public_url: "https://#{hostname}"
      })
    rescue Error => e
      ServiceResponse.failure(error: e.message)
    rescue Faraday::Error => e
      ServiceResponse.failure(error: "Cloudflare API request failed: #{e.message}")
    end

    private

    attr_reader :api_token, :internal_port

    # ─── Cloudflare API calls ───────────────────────────────────────────

    def fetch_account_id
      body = get("/accounts")
      accounts = body["result"] || []
      accounts.first&.dig("id")
    end

    def fetch_zone_for_hostname(account_id, hostname)
      # Try progressively shorter suffixes of the hostname to find the zone
      # (e.g. "hivemind.example.co.uk" -> "example.co.uk" -> "co.uk").
      parts = hostname.split(".")
      (0...(parts.length - 1)).each do |i|
        candidate = parts[i..].join(".")
        body = get("/zones", params: { name: candidate })
        zone = (body["result"] || []).first
        return zone if zone
      end
      nil
    end

    def create_tunnel(account_id, hostname)
      name = "hivemind-#{hostname.parameterize}-#{SecureRandom.hex(3)}"
      body = post("/accounts/#{account_id}/cfd_tunnel", {
        name: name,
        config_src: "cloudflare"
      })

      result = body["result"]
      if body["success"] && result
        { ok: true, id: result["id"], token: result["token"] || fetch_tunnel_token(account_id, result["id"]) }
      else
        { ok: false, error: api_error_message(body, "Failed to create tunnel") }
      end
    end

    def fetch_tunnel_token(account_id, tunnel_id)
      body = get("/accounts/#{account_id}/cfd_tunnel/#{tunnel_id}/token")
      body["result"]
    end

    def configure_ingress(account_id, tunnel_id, hostname)
      body = put("/accounts/#{account_id}/cfd_tunnel/#{tunnel_id}/configurations", {
        config: {
          ingress: [
            { hostname: hostname, service: "http://app:#{internal_port}" },
            { service: "http_status:404" }
          ]
        }
      })

      if body["success"]
        { ok: true }
      else
        { ok: false, error: api_error_message(body, "Failed to configure tunnel ingress") }
      end
    end

    def create_cname(zone_id, hostname, tunnel_id)
      body = post("/zones/#{zone_id}/dns_records", {
        type: "CNAME",
        name: hostname,
        content: "#{tunnel_id}.cfargotunnel.com",
        proxied: true
      })

      if body["success"]
        { ok: true }
      elsif body["errors"].to_a.any? { |e| e["code"] == 81_053 } # record already exists
        { ok: true }
      else
        { ok: false, error: api_error_message(body, "Failed to create DNS record") }
      end
    end

    # ─── HTTP plumbing ───────────────────────────────────────────────────

    def get(path, params: {})
      response = connection.get(full_url(path), params) { |req| apply_headers(req) }
      parse(response)
    end

    def post(path, payload)
      response = connection.post(full_url(path)) do |req|
        apply_headers(req)
        req.body = JSON.generate(payload)
      end
      parse(response)
    end

    def put(path, payload)
      response = connection.put(full_url(path)) do |req|
        apply_headers(req)
        req.body = JSON.generate(payload)
      end
      parse(response)
    end

    def full_url(path)
      "#{API_BASE}#{path}"
    end

    def apply_headers(req)
      req.headers["Authorization"] = "Bearer #{api_token}"
      req.headers["Content-Type"] = "application/json"
    end

    def parse(response)
      JSON.parse(response.body)
    rescue JSON::ParserError
      { "success" => false, "errors" => [ { "message" => "Invalid response from Cloudflare (status #{response.status})" } ] }
    end

    def api_error_message(body, fallback)
      messages = (body["errors"] || []).map { |e| e["message"] }.compact
      messages.any? ? messages.join(", ") : fallback
    end

    def connection
      @connection ||= Faraday.new do |f|
        f.options.timeout = 20
        f.options.open_timeout = 10
        f.adapter Faraday.default_adapter
      end
    end
  end
end
