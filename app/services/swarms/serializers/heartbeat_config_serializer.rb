# frozen_string_literal: true

module Swarms
  module Serializers
    # Serializes the platform's heartbeat configuration into a swarm heartbeat_config entry.
    #
    # Heartbeat config is stored across two Setting records:
    #   "heartbeat"       – JSON blob with enabled, model, provider, interval_minutes,
    #                       prompt, light_context
    #   "heartbeat_tasks" – JSON array of standing checklist items
    #
    # Output schema:
    #   enabled          – boolean
    #   interval_minutes – integer
    #   model            – string (optional)
    #   provider         – string (optional)
    #   prompt           – string (optional)
    #   light_context    – boolean (optional, omitted when false)
    #   checklist        – array of checklist item objects (optional)
    #
    # Returns nil when heartbeat settings have never been configured (no Setting record).
    #
    # Usage:
    #   hash = HeartbeatConfigSerializer.call
    #   # => { "enabled" => true, "interval_minutes" => 30, ... } or nil
    class HeartbeatConfigSerializer
      HEARTBEAT_SETTING_KEY = "heartbeat"
      TASKS_SETTING_KEY     = "heartbeat_tasks"

      def self.call
        new.call
      end

      def call
        raw = Setting.get(HEARTBEAT_SETTING_KEY)
        return nil if raw.nil?

        config = begin
          JSON.parse(raw)
        rescue JSON::ParserError
          {}
        end

        config = config.with_indifferent_access

        hash = {}
        hash["enabled"]          = config[:enabled] == true || config[:enabled] == "true"
        hash["interval_minutes"] = config[:interval_minutes].to_i if config[:interval_minutes].present?
        hash["model"]            = config[:model].to_s             if config[:model].present?
        hash["provider"]         = config[:provider].to_s          if config[:provider].present?
        hash["prompt"]           = config[:prompt].to_s            if config[:prompt].present?
        hash["light_context"]    = true                             if config[:light_context] == true || config[:light_context] == "true"

        checklist = load_checklist
        hash["checklist"] = checklist if checklist.any?

        hash
      end

      private

      def load_checklist
        raw = Setting.get(TASKS_SETTING_KEY)
        return [] unless raw

        items = begin
          JSON.parse(raw)
        rescue JSON::ParserError
          []
        end

        return [] unless items.is_a?(Array)

        # Only export protected (standing) checklist items — ephemeral one-off
        # tasks have no meaning outside this heartbeat cycle.
        items.select { |item| item.is_a?(Hash) && item["protected"] == true }
             .map { |item| { "task" => item["task"].to_s }.compact }
             .reject { |item| item["task"].blank? }
      end
    end
  end
end
