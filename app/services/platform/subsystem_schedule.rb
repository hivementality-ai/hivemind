# frozen_string_literal: true

module Platform
  # Owns the recurring jobs that only matter once a subsystem is switched on.
  # A job whose subsystem is off has no cron entry at all, so an idle install
  # pays nothing for it; switching it on registers the entry, switching it
  # off removes it. Backed by sidekiq-cron, so the web process can flip a
  # job on and the worker picks it up from Redis.
  module SubsystemSchedule
    Entry = Struct.new(:name, :cron, :job_class, :description, :switched_on, keyword_init: true)

    ENTRIES = [
      Entry.new(
        name: "heartbeat",
        cron: "* * * * *", # the job itself checks the configured interval
        job_class: "HeartbeatJob",
        description: "Agent heartbeat — periodic check-ins for autonomous behavior",
        switched_on: -> { heartbeat_enabled? }
      ),
      Entry.new(
        name: "update_check",
        cron: "0 9 * * *",
        job_class: "UpdateCheckJob",
        description: "Check GitHub for new Hivemind releases",
        switched_on: -> { update_check_enabled? }
      ),
      Entry.new(
        name: "remote_access_health_check",
        cron: "*/5 * * * *",
        job_class: "RemoteAccessHealthCheckJob",
        description: "Re-verify the configured public URL + /cable WebSocket handshake",
        switched_on: -> { RemoteAccess::ConfigStore.configured? }
      )
    ].freeze

    # Settings whose change can flip an entry on or off.
    WATCHED_SETTING_KEYS = %w[heartbeat canonical_host remote_access_mode].freeze

    class << self
      # Registers the entries that are switched on and removes the rest.
      def reconcile!
        ENTRIES.each do |entry|
          if instance_exec(&entry.switched_on)
            Sidekiq::Cron::Job.create(
              name: entry.name, cron: entry.cron, class: entry.job_class, description: entry.description
            )
          else
            Sidekiq::Cron::Job.destroy(entry.name)
          end
        end
      rescue StandardError => e
        Rails.logger.warn("[SubsystemSchedule] Reconcile failed: #{e.message}")
      end

      # @return [Boolean] whether the heartbeat is switched on in its settings
      def heartbeat_enabled?
        raw = Setting.get("heartbeat")
        raw.present? && JSON.parse(raw)["enabled"] == true
      rescue JSON::ParserError
        false
      end

      # @return [Boolean] false only when the operator opted out via the environment
      def update_check_enabled?
        ENV.fetch("UPDATE_CHECK_ENABLED", "true") != "false"
      end
    end
  end
end
