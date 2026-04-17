# frozen_string_literal: true

module Swarms
  module AgentConfig
    # Applies a tool_loop_config hash from a swarm agent definition to an Agent record.
    #
    # Called by AgentsDeployer after the agent record has been created or updated.
    # Only updates the tool_loop_config column when a non-blank config is supplied.
    #
    # Stores the config as-is — Agent#effective_tool_loop_config deep-merges it
    # with DEFAULT_LOOP_CONFIG at runtime, so only the overrides need persisting.
    #
    # Usage:
    #   result = ToolLoopConfigDeployer.call(agent: record, config: hash_or_nil)
    #   result.success?  # => true / false
    #   result.message   # => error string on failure
    class ToolLoopConfigDeployer
      def self.call(agent:, config:)
        new(agent, config).call
      end

      def initialize(agent, config)
        @agent  = agent
        @config = config
      end

      def call
        return ServiceResponse.success(payload: { applied: false }) if @config.blank?

        validation = ToolLoopConfigValidator.call(config: @config)
        return validation unless validation.success?

        @agent.update!(tool_loop_config: @config)

        ServiceResponse.success(payload: { applied: true })
      rescue ActiveRecord::RecordInvalid => e
        ServiceResponse.error(message: "Failed to apply tool loop config: #{e.record.errors.full_messages.join(', ')}")
      end
    end
  end
end
