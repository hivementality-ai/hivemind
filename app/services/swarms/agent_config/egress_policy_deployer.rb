# frozen_string_literal: true

module Swarms
  module AgentConfig
    # Applies an egress_policy hash from a swarm agent definition to an Agent record.
    #
    # Called by AgentsDeployer after the agent record has been created or updated.
    # The agent is already persisted — this deployer only updates the egress_policy
    # column when a non-blank policy is supplied.
    #
    # Validation runs first via EgressPolicyValidator. If the policy is invalid,
    # the deployer returns an error ServiceResponse and the calling deployer should
    # propagate the failure (rolling back the transaction).
    #
    # Usage:
    #   result = EgressPolicyDeployer.call(agent: record, policy: hash_or_nil)
    #   result.success?  # => true / false
    #   result.message   # => error string on failure
    class EgressPolicyDeployer
      def self.call(agent:, policy:)
        new(agent, policy).call
      end

      def initialize(agent, policy)
        @agent  = agent
        @policy = policy
      end

      def call
        # nil/blank policy is a no-op — leave whatever the agent already has
        return ServiceResponse.success(payload: { applied: false }) if @policy.blank?

        validation = EgressPolicyValidator.call(policy: @policy)
        return validation unless validation.success?

        @agent.update!(egress_policy: @policy)

        ServiceResponse.success(payload: { applied: true })
      rescue ActiveRecord::RecordInvalid => e
        ServiceResponse.error(message: "Failed to apply egress policy: #{e.record.errors.full_messages.join(', ')}")
      end
    end
  end
end
