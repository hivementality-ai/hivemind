# frozen_string_literal: true

# Schedule recurring jobs via sidekiq-cron
# HeartbeatJob runs every minute and internally checks which agents are due

if defined?(Sidekiq::Cron)
  Sidekiq.configure_server do |config|
    config.on(:startup) do
      Sidekiq::Cron::Job.create(
        name: "heartbeat",
        cron: "* * * * *", # Every minute — the job itself checks per-agent intervals
        class: "HeartbeatJob",
        description: "Agent heartbeat — periodic check-ins for autonomous behavior"
      )

      Sidekiq::Cron::Job.create(
        name: "update_check",
        cron: "0 9 * * *", # Daily at 9 AM
        class: "UpdateCheckJob",
        description: "Check GitHub for new Hivemind releases"
      )

      Sidekiq::Cron::Job.create(
        name: "remote_access_health_check",
        cron: "*/5 * * * *", # Every 5 minutes — no-op unless remote access is configured
        class: "RemoteAccessHealthCheckJob",
        description: "Re-verify the configured public URL + /cable WebSocket handshake"
      )
    end
  end
end
