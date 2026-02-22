# frozen_string_literal: true

# Start Discord Gateway connections when the app boots (in server mode only).
# This connects all configured Discord agent bots to the Discord Gateway
# for real-time message reception.
#
# Gateway connections are managed in-memory and will reconnect automatically
# on disconnect. They run in background threads.
#
# To manually manage connections:
#   Channels::DiscordGateway.connect_all
#   Channels::DiscordGateway.disconnect_all
#   Channels::DiscordGateway.status

Rails.application.config.after_initialize do
  # Only start in server mode (not console, rake tasks, etc.)
  # Check for Puma or Sidekiq server context
  if defined?(Rails::Server) || defined?(Puma) || (defined?(Sidekiq) && Sidekiq.server?)
    # Delay startup to let the app fully initialize
    Thread.new do
      sleep(5) # Wait for DB connections to be ready
      begin
        if Channel.where(channel_type: "discord", enabled: true).exists?
          Rails.logger.info("[DiscordGateway] Starting gateway connections...")
          Channels::DiscordGateway.connect_all
        end
      rescue StandardError => e
        Rails.logger.error("[DiscordGateway] Failed to start: #{e.message}")
      end
    end
  end
end
