# frozen_string_literal: true

module Channels
  # Maps channel records to the docker compose profiles whose services they
  # need (docker-compose.yml: `connector` is profile "channels", `signal-cli`
  # is profile "signal"), and keeps COMPOSE_PROFILES in the host .env in step
  # so `hivemind update/start` bring those services back up.
  module ComposeProfiles
    CONNECTOR_PROFILE = "channels"
    SIGNAL_PROFILE = "signal"
    CONNECTOR_TYPES = %w[slack telegram whatsapp signal].freeze
    SERVICES = { CONNECTOR_PROFILE => "connector", SIGNAL_PROFILE => "signal-cli" }.freeze
    ENV_FILE = "/host-hivemind/.env"

    module_function

    # @param channel_types [Array<String>]
    # @return [Array<String>] profiles needed to serve those channel types
    def for_types(channel_types)
      types = Array(channel_types).map(&:to_s)
      profiles = []
      profiles << CONNECTOR_PROFILE if types.intersect?(CONNECTOR_TYPES)
      profiles << SIGNAL_PROFILE if types.include?("signal")
      profiles
    end

    # @return [Array<String>] profiles needed by the enabled channel records
    def needed
      for_types(Channel.enabled_channels.distinct.pluck(:channel_type))
    end

    # Combines comma-separated profile lists, keeping order and dropping blanks and repeats.
    #
    # @return [String]
    def merge(*lists)
      lists.flat_map { |list| list.to_s.split(",") }.map(&:strip).reject(&:blank?).uniq.join(",")
    end

    # Adds the profiles to COMPOSE_PROFILES in the host .env (never removes any).
    #
    # @return [Boolean] whether the file was written
    def persist(profiles, path: ENV_FILE)
      return false if profiles.empty? || !File.file?(path)

      lines = File.readlines(path)
      index = lines.index { |line| line.start_with?("COMPOSE_PROFILES=") }
      current = index ? lines[index].sub("COMPOSE_PROFILES=", "").strip.delete("\"'") : ""
      merged = merge(current, profiles.join(","))
      return false if merged == current

      entry = "COMPOSE_PROFILES=#{merged}\n"
      if index
        lines[index] = entry
      else
        lines << "\n" unless lines.empty? || lines.last.end_with?("\n")
        lines << entry
      end
      File.write(path, lines.join)
      true
    end

    # Starts the services a channel needs. Call after the channel is saved.
    #
    # @return [ServiceResponse, nil] nil when the channel needs nothing
    def ensure_running(channel)
      return unless channel.enabled?

      profiles = for_types([ channel.channel_type ])
      return if profiles.empty?

      persist(profiles)
      RemoteAccess::ConnectorManager.new.up(profiles.map { |p| SERVICES.fetch(p) }, profiles: profiles)
    end
  end
end
