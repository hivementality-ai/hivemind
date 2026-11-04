# frozen_string_literal: true

# Periodically re-verifies the configured public URL (HTTP + /cable
# WebSocket handshake) so the Remote Access status card can show connector
# up/down and a fresh last-check time without the admin visiting the page.
# Runs via sidekiq-cron (see config/initializers/sidekiq_cron.rb); a no-op
# until remote access is configured.
class RemoteAccessHealthCheckJob < ApplicationJob
  queue_as :low

  def perform
    return unless RemoteAccess::ConfigStore.configured?

    host = RemoteAccess::ConfigStore.canonical_host
    return if host.blank?

    result = RemoteAccess::HealthCheck.call(host)
    checks = result.payload || result.data

    RemoteAccess::ConfigStore.record_check_result(
      http_ok: checks&.dig(:http, :ok) || false,
      websocket_ok: checks&.dig(:websocket, :ok) || false,
      error: result.success? ? nil : result.error
    )
  rescue StandardError => e
    Rails.logger.warn("[RemoteAccessHealthCheckJob] Failed: #{e.message}")
  end
end
