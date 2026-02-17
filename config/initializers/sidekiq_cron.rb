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
    end
  end
end
