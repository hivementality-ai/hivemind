# frozen_string_literal: true

module RemoteAccess
  # Reads/writes Remote Access configuration through the app's existing
  # settings primitives: `Setting` (plain key/value, e.g. canonical host,
  # mode, status) and `VaultEntry` (server-side encrypted, e.g. the
  # Cloudflare API token and tunnel run token) — the same split every other
  # integration in the app uses (see IntegrationsController).
  module ConfigStore
    VAULT_NAMESPACE = "remote_access"

    MODES = %w[byo cloudflare].freeze

    class << self
      # ─── Canonical host (extends the app's existing host setting) ───────

      def canonical_host
        Setting.get("canonical_host")
      end

      def canonical_host=(url)
        Setting.set("canonical_host", url)
      end

      def mode
        Setting.get("remote_access_mode")
      end

      def mode=(value)
        raise ArgumentError, "invalid mode: #{value}" if value.present? && !MODES.include?(value.to_s)
        Setting.set("remote_access_mode", value.to_s)
      end

      def configured?
        canonical_host.present? && mode.present?
      end

      # ─── Cloudflare-specific plain settings ──────────────────────────────

      def cloudflare_tunnel_id
        Setting.get("cloudflare_tunnel_id")
      end

      def cloudflare_tunnel_id=(value)
        Setting.set("cloudflare_tunnel_id", value)
      end

      def cloudflare_account_id
        Setting.get("cloudflare_account_id")
      end

      def cloudflare_account_id=(value)
        Setting.set("cloudflare_account_id", value)
      end

      def cloudflare_zone_id
        Setting.get("cloudflare_zone_id")
      end

      def cloudflare_zone_id=(value)
        Setting.set("cloudflare_zone_id", value)
      end

      # ─── Secrets (encrypted via VaultEntry) ──────────────────────────────

      def cloudflare_api_token
        vault_get("cloudflare_api_token")
      end

      def cloudflare_api_token=(value)
        vault_set("cloudflare_api_token", value)
      end

      def cloudflare_tunnel_token
        vault_get("cloudflare_tunnel_token")
      end

      def cloudflare_tunnel_token=(value)
        vault_set("cloudflare_tunnel_token", value)
      end

      # ─── Health/status (fed by RemoteAccess::HealthCheck + the recurring job) ─

      def last_check_at
        raw = Setting.get("remote_access_last_check_at")
        raw.present? ? Time.zone.parse(raw) : nil
      rescue ArgumentError
        nil
      end

      def record_check_result(http_ok:, websocket_ok:, error: nil)
        Setting.set("remote_access_last_check_at", Time.current.iso8601)
        Setting.set("remote_access_http_ok", http_ok ? "true" : "false")
        Setting.set("remote_access_websocket_ok", websocket_ok ? "true" : "false")
        Setting.set("remote_access_last_error", error.to_s)
      end

      def http_ok?
        Setting.get("remote_access_http_ok") == "true"
      end

      def websocket_ok?
        Setting.get("remote_access_websocket_ok") == "true"
      end

      def last_error
        Setting.get("remote_access_last_error").presence
      end

      # ─── Reset ────────────────────────────────────────────────────────

      def clear!
        %w[
          canonical_host remote_access_mode
          cloudflare_tunnel_id cloudflare_account_id cloudflare_zone_id
          remote_access_last_check_at remote_access_http_ok remote_access_websocket_ok remote_access_last_error
        ].each { |key| Setting.set(key, nil) }

        VaultEntry.global.in_namespace(VAULT_NAMESPACE).destroy_all
      end

      private

      def vault_get(key)
        VaultEntry.resolve(namespace: VAULT_NAMESPACE, key: key)&.value
      end

      def vault_set(key, value)
        entry = VaultEntry.find_or_initialize_by(namespace: VAULT_NAMESPACE, key: key, agent_id: nil)
        entry.encrypted_value = value
        entry.save!
      end
    end
  end
end
