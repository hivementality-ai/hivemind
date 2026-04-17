# frozen_string_literal: true

module Swarms
  module AgentConfig
    # Validates a budget_limits hash from a swarm agent definition.
    #
    # The budget_limits key encodes per-agent cost controls that map to:
    #   - agent.daily_budget_limit   (decimal)
    #   - agent.monthly_budget_limit (decimal)
    #   - agent_budgets rows         (period-based tracked limits)
    #
    # Expected shape:
    #   {
    #     "daily_limit"   => 10.0,      # optional — maps to daily_budget_limit
    #     "monthly_limit" => 100.0,     # optional — maps to monthly_budget_limit
    #     "periods"       => [          # optional — maps to agent_budgets rows
    #       { "period" => "daily",   "limit_cents" => 1000 },
    #       { "period" => "weekly",  "limit_cents" => 5000 },
    #       { "period" => "monthly", "limit_cents" => 20000 }
    #     ]
    #   }
    #
    # Rules:
    #   - Must be a Hash (if present)
    #   - daily_limit/monthly_limit — must be positive numerics when present
    #   - periods — must be an Array of Hashes
    #   - Each period entry must have a valid period string and positive limit_cents integer
    #
    # Usage:
    #   result = BudgetLimitsValidator.call(budget_limits: hash)
    #   result.success?          # => true  (valid or nil/empty)
    #   result.error?            # => true
    #   result.payload[:errors]  # => Array<String>
    class BudgetLimitsValidator
      VALID_PERIODS   = %w[daily weekly monthly].freeze
      NUMERIC_LIMIT_KEYS = %w[daily_limit monthly_limit].freeze

      def self.call(budget_limits:)
        new(budget_limits).call
      end

      def initialize(budget_limits)
        @budget_limits = budget_limits
        @errors        = []
      end

      def call
        return ServiceResponse.success(payload: { errors: [] }) if @budget_limits.blank?

        unless @budget_limits.is_a?(Hash)
          @errors << "budget_limits must be an object"
          return failure
        end

        b = @budget_limits.with_indifferent_access

        validate_numeric_limits(b)
        validate_periods(b)

        @errors.any? ? failure : ServiceResponse.success(payload: { errors: [] })
      end

      private

      def validate_numeric_limits(b)
        NUMERIC_LIMIT_KEYS.each do |key|
          next unless b.key?(key) && !b[key].nil?

          val = b[key]
          unless (val.is_a?(Numeric)) && val > 0
            @errors << "budget_limits.#{key} must be a positive number"
          end
        end
      end

      def validate_periods(b)
        return unless b.key?(:periods) && !b[:periods].nil?

        unless b[:periods].is_a?(Array)
          @errors << "budget_limits.periods must be an array"
          return
        end

        b[:periods].each_with_index do |entry, i|
          unless entry.is_a?(Hash)
            @errors << "budget_limits.periods[#{i}] must be an object"
            next
          end

          e = entry.with_indifferent_access

          period = e[:period]
          if period.blank?
            @errors << "budget_limits.periods[#{i}].period is required"
          elsif !VALID_PERIODS.include?(period.to_s)
            @errors << "budget_limits.periods[#{i}].period '#{period}' is invalid (must be one of: #{VALID_PERIODS.join(', ')})"
          end

          limit = e[:limit_cents]
          if limit.nil?
            @errors << "budget_limits.periods[#{i}].limit_cents is required"
          elsif !(limit.is_a?(Integer)) || limit < 1
            @errors << "budget_limits.periods[#{i}].limit_cents must be a positive integer"
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
