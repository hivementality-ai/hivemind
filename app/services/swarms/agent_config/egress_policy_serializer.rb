# frozen_string_literal: true

module Swarms
  module AgentConfig
    # Serializes an agent's egress_policy into a swarm-export-safe Hash.
    #
    # The egress_policy jsonb column stores:
    #   { "mode" => "allowlist"|"blocklist"|"disabled",
    #     "rules" => [{ "pattern" => "...", "port" => 443 }, ...],
    #     "log_blocked" => true|false }
    #
    # Serialization rules:
    #   - Returns nil when the policy is blank or has no mode set (omit from output)
    #   - Returns a clean Hash with only the non-blank fields present
    #
    # Usage:
    #   hash = EgressPolicySerializer.call(agent: agent_record)
    #   # => { "mode" => "allowlist", "rules" => [...] }  or  nil
    class EgressPolicySerializer
      def self.call(agent:)
        new(agent).call
      end

      def initialize(agent)
        @agent = agent
      end

      def call
        policy = @agent.egress_policy
        return nil if policy.blank? || !policy.is_a?(Hash)

        p = policy.with_indifferent_access
        return nil if p[:mode].blank?

        result = { "mode" => p[:mode].to_s }

        rules = Array(p[:rules]).reject(&:blank?)
        result["rules"] = rules.map { |r| serialize_rule(r) } if rules.any?

        result["log_blocked"] = p[:log_blocked] if p.key?(:log_blocked) && !p[:log_blocked].nil?

        result
      end

      private

      def serialize_rule(rule)
        r = rule.with_indifferent_access
        entry = { "pattern" => r[:pattern].to_s }
        entry["port"] = r[:port].to_i if r[:port].present?
        entry
      end
    end
  end
end
