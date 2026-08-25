# frozen_string_literal: true

require "net/http"

module Api
  module V1
    class SystemController < ApiController
      skip_before_action :authenticate_api_token, only: [ :version ]

      # GET /api/v1/system/version
      def version
        if update_check_enabled?
          info = GithubReleaseChecker.update_info
          render json: info || { current: Hivemind::VERSION, error: "Unable to check for updates" }
        else
          render json: {
            current: Hivemind::VERSION,
            update_check_enabled: false
          }
        end
      end

      # GET /api/v1/system/provider_health
      #
      # The signal that was missing during the 2026-08-24 outage. Distinguishes
      # "the provider refused us" (circuit open, with the real reason) from
      # "we cannot open a socket at all" (local port exhaustion) from healthy.
      # Returns 503 when degraded so an uptime monitor can alarm on it.
      def provider_health
        circuits = Providers::CircuitBreaker.open_circuits
        proxy = sdk_proxy_health

        port_exhausted = circuits.any? { |c| c.reason == "local_port_exhaustion" }
        degraded = circuits.any? || proxy[:degraded]

        render status: (degraded ? :service_unavailable : :ok), json: {
          status: degraded ? "degraded" : "ok",
          reason: degraded ? degraded_reason(circuits, proxy, port_exhausted) : nil,
          can_open_sockets: !port_exhausted,
          circuits: circuits.map do |c|
            {
              provider: c.provider, credential: c.credential, state: c.state,
              reason: c.reason, consecutive_failures: c.failures,
              opened_at: c.opened_at&.iso8601, message: c.message
            }
          end,
          sdk_proxy: proxy
        }
      end

      private

      def degraded_reason(circuits, proxy, port_exhausted)
        return "cannot bind outbound sockets: host ephemeral port pool exhausted" if port_exhausted
        return "provider circuit open: #{circuits.first.reason}" if circuits.any?

        "sdk-proxy degraded: #{proxy[:reason]}"
      end

      # Best-effort read of the proxy's own view. Its ceilings and in-flight
      # count live there, not here.
      def sdk_proxy_health
        uri = URI("#{Providers::AnthropicAdapter::SDK_PROXY_URL}/health")
        response = Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 2) do |http|
          http.get(uri.path)
        end
        JSON.parse(response.body).symbolize_keys
      rescue StandardError => e
        { reachable: false, degraded: true, reason: "sdk-proxy unreachable: #{e.message}" }
      end

      def update_check_enabled?
        ENV.fetch("UPDATE_CHECK_ENABLED", "true") != "false"
      end
    end
  end
end
