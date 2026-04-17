# frozen_string_literal: true

module Swarms
  module AgentConfig
    # Serializes an agent's tool_loop_config into a swarm-export-safe Hash.
    #
    # The tool_loop_config jsonb column stores override values that are
    # deep-merged on top of Agent::DEFAULT_LOOP_CONFIG at runtime.
    #
    # Serialization rules:
    #   - Returns nil when config is blank or empty (omit from output)
    #   - Returns nil when config exactly matches the default (no need to round-trip defaults)
    #   - Otherwise returns the stored hash as-is — it is already in swarm format
    #
    # The inverse operation is AgentsDeployer applying the hash directly to the
    # agent's tool_loop_config column via build_attributes.
    #
    # Usage:
    #   hash = ToolLoopConfigSerializer.call(agent: agent_record)
    #   # => { "history_size" => 50, ... }  or  nil
    class ToolLoopConfigSerializer
      def self.call(agent:)
        new(agent).call
      end

      def initialize(agent)
        @agent = agent
      end

      def call
        cfg = @agent.tool_loop_config
        return nil if cfg.blank? || !cfg.is_a?(Hash) || cfg.empty?

        # Skip when the stored value is the same as the compiled default —
        # no value in round-tripping what every agent already has by default.
        return nil if cfg == Agent::DEFAULT_LOOP_CONFIG.deep_stringify_keys

        cfg
      end
    end
  end
end
