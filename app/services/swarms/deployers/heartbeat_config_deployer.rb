# frozen_string_literal: true

module Swarms
  module Deployers
    # Applies heartbeat configuration from a SwarmDocument's heartbeat_config section.
    #
    # Updates the platform's Setting records:
    #   "heartbeat"       – JSON blob with enabled, model, provider, interval_minutes,
    #                       prompt, light_context
    #   "heartbeat_tasks" – JSON array of standing checklist items
    #
    # This deployer always overwrites — heartbeat config is a singleton (there is
    # only one global heartbeat configuration), so no conflict resolution is needed.
    # If the swarm file has a heartbeat_config block, it is applied. If not, the
    # existing platform config is left unchanged.
    #
    # Usage:
    #   result = HeartbeatConfigDeployer.call(document: swarm_doc)
    #   result.success?
    #   result.payload[:heartbeat_config]  # => :applied | :skipped
    class HeartbeatConfigDeployer
      HEARTBEAT_SETTING_KEY = "heartbeat"
      TASKS_SETTING_KEY     = "heartbeat_tasks"

      DeployResult = Data.define(:action) do
        # action – :applied | :skipped
      end

      def self.call(document:)
        new(document).call
      end

      def initialize(document)
        @document = document
      end

      def call
        config = @document.heartbeat_config

        if config.nil? || !config.is_a?(Hash)
          return ServiceResponse.success(payload: { heartbeat_config: DeployResult.new(action: :skipped) })
        end

        apply_config(config.with_indifferent_access)

        ServiceResponse.success(payload: { heartbeat_config: DeployResult.new(action: :applied) })
      rescue StandardError => e
        ServiceResponse.error(message: "Failed to deploy heartbeat config: #{e.message}")
      end

      private

      def apply_config(config)
        settings = build_settings_hash(config)
        Setting.set(HEARTBEAT_SETTING_KEY, settings.to_json)

        checklist = Array(config[:checklist])
        if checklist.any?
          items = checklist.map do |item|
            item = item.with_indifferent_access
            {
              "task"      => item[:task].to_s,
              "protected" => true
            }
          end.reject { |item| item["task"].blank? }

          Setting.set(TASKS_SETTING_KEY, items.to_json)
        end
      end

      def build_settings_hash(config)
        settings = {}

        settings["enabled"]          = config[:enabled] == true || config[:enabled] == "true"
        settings["interval_minutes"] = config[:interval_minutes].to_i if config[:interval_minutes].present?
        settings["model"]            = config[:model].to_s             if config[:model].present?
        settings["provider"]         = config[:provider].to_s          if config[:provider].present?
        settings["prompt"]           = config[:prompt].to_s            if config[:prompt].present?
        settings["light_context"]    = config[:light_context] == true  if config.key?(:light_context)

        settings
      end
    end
  end
end
