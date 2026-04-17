# frozen_string_literal: true

module Swarms
  module AgentConfig
    # Serializes an agent's budget configuration into a swarm-export-safe Hash.
    #
    # Reads from two sources on the agent record:
    #   1. agent.daily_budget_limit   — decimal column (platform default: 10.0)
    #   2. agent.monthly_budget_limit — decimal column (platform default: 100.0)
    #   3. agent.agent_budgets        — has_many tracked period budgets
    #
    # Serialization rules:
    #   - daily_limit   included when set and differs from the platform default
    #   - monthly_limit included when set and differs from the platform default
    #   - periods       included when any AgentBudget rows exist (full list)
    #   - Returns nil when there is nothing non-default to serialize
    #
    # Output shape:
    #   {
    #     "daily_limit"   => 25.0,
    #     "monthly_limit" => 200.0,
    #     "periods" => [
    #       { "period" => "daily",   "limit_cents" => 2500 },
    #       { "period" => "monthly", "limit_cents" => 20000 }
    #     ]
    #   }
    #
    # Usage:
    #   hash = BudgetLimitsSerializer.call(agent: agent_record)
    #   # => Hash  or  nil
    class BudgetLimitsSerializer
      # Platform defaults from schema — omit these from export to keep files concise.
      DEFAULT_DAILY_LIMIT   = BigDecimal("10.0")
      DEFAULT_MONTHLY_LIMIT = BigDecimal("100.0")

      def self.call(agent:)
        new(agent).call
      end

      def initialize(agent)
        @agent = agent
      end

      def call
        result = {}

        serialize_column_limits(result)
        serialize_period_budgets(result)

        result.any? ? result : nil
      end

      private

      def serialize_column_limits(result)
        daily = @agent.daily_budget_limit
        if daily.present? && daily.to_d != DEFAULT_DAILY_LIMIT
          result["daily_limit"] = daily.to_f
        end

        monthly = @agent.monthly_budget_limit
        if monthly.present? && monthly.to_d != DEFAULT_MONTHLY_LIMIT
          result["monthly_limit"] = monthly.to_f
        end
      end

      def serialize_period_budgets(result)
        budgets = @agent.agent_budgets.order(:period)
        return if budgets.empty?

        result["periods"] = budgets.map do |budget|
          entry = {
            "period"      => budget.period.to_s,
            "limit_cents" => budget.limit_cents.to_i
          }
          entry
        end
      end
    end
  end
end
