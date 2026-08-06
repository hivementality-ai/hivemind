# frozen_string_literal: true

module Delegations
  # Delegation guardrail configuration, stored as a JSON blob under the
  # "delegation" Setting key (same pattern as the "heartbeat" setting).
  # Values are clamped to hard system ceilings so a bad setting can never
  # disable runaway protection.
  class Config
    SETTING_KEY = "delegation"

    DEFAULTS = {
      "max_depth" => 3,
      "max_concurrent_per_session" => 5,
      "dedup_pending" => true
    }.freeze

    CEILINGS = {
      "max_depth" => 5,
      "max_concurrent_per_session" => 20
    }.freeze

    def self.max_depth
      fetch_int("max_depth")
    end

    def self.max_concurrent_per_session
      fetch_int("max_concurrent_per_session")
    end

    def self.dedup_pending?
      value = raw["dedup_pending"]
      value.nil? ? DEFAULTS["dedup_pending"] : !!value
    end

    def self.raw
      stored = Setting.get(SETTING_KEY)
      return DEFAULTS unless stored

      DEFAULTS.merge(JSON.parse(stored))
    rescue JSON::ParserError
      DEFAULTS
    end

    def self.fetch_int(key)
      raw[key].to_i.clamp(1, CEILINGS[key])
    end
    private_class_method :fetch_int
  end
end
