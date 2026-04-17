# frozen_string_literal: true

module Swarms
  module AgentConfig
    # Validates a tool_loop_config hash from a swarm agent definition.
    #
    # Rules:
    #   - Must be a Hash (if present)
    #   - history_size, warning_threshold, critical_threshold,
    #     circuit_breaker_threshold — if present, must be positive integers
    #   - warning_threshold < critical_threshold < circuit_breaker_threshold
    #     (enforced when multiple thresholds are supplied together)
    #   - detectors, if present, must be a Hash with boolean values
    #
    # Usage:
    #   result = ToolLoopConfigValidator.call(config: hash)
    #   result.success?          # => true  (config is valid or nil/empty)
    #   result.error?            # => true  (config has validation errors)
    #   result.payload[:errors]  # => Array<String>
    class ToolLoopConfigValidator
      POSITIVE_INTEGER_KEYS = %w[
        history_size
        warning_threshold
        critical_threshold
        circuit_breaker_threshold
      ].freeze

      KNOWN_DETECTORS = %w[generic_repeat ping_pong no_progress].freeze

      def self.call(config:)
        new(config).call
      end

      def initialize(config)
        @config = config
        @errors = []
      end

      def call
        return ServiceResponse.success(payload: { errors: [] }) if @config.blank?

        unless @config.is_a?(Hash)
          @errors << "tool_loop_config must be an object"
          return failure
        end

        c = @config.with_indifferent_access

        validate_positive_integers(c)
        validate_threshold_ordering(c)
        validate_detectors(c)

        @errors.any? ? failure : ServiceResponse.success(payload: { errors: [] })
      end

      private

      def validate_positive_integers(c)
        POSITIVE_INTEGER_KEYS.each do |key|
          next unless c.key?(key) && !c[key].nil?

          val = c[key]
          unless val.is_a?(Integer) && val >= 1
            @errors << "tool_loop_config.#{key} must be a positive integer"
          end
        end
      end

      def validate_threshold_ordering(c)
        warning  = c[:warning_threshold]
        critical = c[:critical_threshold]
        breaker  = c[:circuit_breaker_threshold]

        # Only validate ordering when all three are present and individually valid
        return unless [warning, critical, breaker].all? { |v| v.is_a?(Integer) && v >= 1 }

        if warning >= critical
          @errors << "tool_loop_config.warning_threshold must be less than critical_threshold"
        end

        if critical >= breaker
          @errors << "tool_loop_config.critical_threshold must be less than circuit_breaker_threshold"
        end
      end

      def validate_detectors(c)
        return unless c.key?(:detectors) && !c[:detectors].nil?

        detectors = c[:detectors]
        unless detectors.is_a?(Hash)
          @errors << "tool_loop_config.detectors must be an object"
          return
        end

        detectors.each do |key, val|
          unless [true, false].include?(val)
            @errors << "tool_loop_config.detectors.#{key} must be a boolean"
          end
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
