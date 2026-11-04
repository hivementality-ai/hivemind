# frozen_string_literal: true

# Subsystem jobs (heartbeat, update check, remote access health check) are
# registered only while their subsystem is switched on. See
# Platform::SubsystemSchedule; Setting keeps the entries in step afterwards.

if defined?(Sidekiq::Cron)
  Sidekiq.configure_server do |config|
    config.on(:startup) { Platform::SubsystemSchedule.reconcile! }
  end
end
