# frozen_string_literal: true

module Swarms
  module AgentConfig
    # Validates an egress_policy hash from a swarm agent definition.
    #
    # Rules:
    #   - Must be a Hash
    #   - mode, if present, must be one of: allowlist, blocklist, disabled
    #   - rules, if present, must be an Array of Hashes each with a non-blank pattern
    #   - Each rule's port, if present, must be an integer 1–65535
    #   - log_blocked, if present, must be a boolean
    #
    # Usage:
    #   result = EgressPolicyValidator.call(policy: hash)
    #   result.success?          # => true  (policy is valid or nil/empty)
    #   result.error?            # => true  (policy has validation errors)
    #   result.payload[:errors]  # => Array<String>
    class EgressPolicyValidator
      VALID_MODES = %w[allowlist blocklist disabled].freeze

      def self.call(policy:)
        new(policy).call
      end

      def initialize(policy)
        @policy = policy
        @errors = []
      end

      def call
        # nil/blank policy is valid — the field is optional.
        # Note: [].blank? is true in Rails, but an empty Array is still the wrong
        # type so we must not short-circuit on it.
        return ServiceResponse.success(payload: { errors: [] }) if @policy.nil? || (@policy.is_a?(Hash) && @policy.empty?)

        unless @policy.is_a?(Hash)
          @errors << "egress_policy must be an object"
          return failure
        end

        p = @policy.with_indifferent_access

        validate_mode(p)
        validate_rules(p)
        validate_log_blocked(p)

        @errors.any? ? failure : ServiceResponse.success(payload: { errors: [] })
      end

      private

      def validate_mode(p)
        mode = p[:mode]
        return if mode.blank?

        unless VALID_MODES.include?(mode.to_s)
          @errors << "egress_policy.mode '#{mode}' is invalid (must be one of: #{VALID_MODES.join(', ')})"
        end
      end

      def validate_rules(p)
        return unless p.key?(:rules) && !p[:rules].nil?

        unless p[:rules].is_a?(Array)
          @errors << "egress_policy.rules must be an array"
          return
        end

        p[:rules].each_with_index do |rule, i|
          unless rule.is_a?(Hash)
            @errors << "egress_policy.rules[#{i}] must be an object"
            next
          end

          r = rule.with_indifferent_access
          @errors << "egress_policy.rules[#{i}] must have a non-blank pattern" if r[:pattern].blank?

          next unless r.key?(:port) && !r[:port].nil?

          port = r[:port]
          unless port.is_a?(Integer) && port >= 1 && port <= 65_535
            @errors << "egress_policy.rules[#{i}].port must be an integer between 1 and 65535"
          end
        end
      end

      def validate_log_blocked(p)
        return unless p.key?(:log_blocked) && !p[:log_blocked].nil?

        unless [true, false].include?(p[:log_blocked])
          @errors << "egress_policy.log_blocked must be a boolean"
        end
      end

      def failure
        ServiceResponse.error(
          message: @errors.first,
          payload: { errors: @errors }
        )
      end
    end
  end
end
