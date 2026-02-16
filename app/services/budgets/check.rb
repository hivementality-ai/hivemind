# frozen_string_literal: true

module Budgets
  # Check if agent has budget remaining
  class Check
    def self.call(agent:, estimated_cost_cents: 0)
      new(agent: agent, estimated_cost_cents: estimated_cost_cents).call
    end

    def initialize(agent:, estimated_cost_cents: 0)
      @agent = agent
      @estimated_cost_cents = estimated_cost_cents
    end

    def call
      # Get active budgets for this agent
      budgets = AgentBudget.where(agent: @agent)

      # If no budgets configured, allow by default
      return ServiceResponse.success(data: { allowed: true, unlimited: true }) if budgets.empty?

      # Check each budget period
      results = budgets.map do |budget|
        check_budget(budget)
      end

      # If any budget is exceeded, deny
      exceeded = results.any? { |r| r[:exceeded] }
      warnings = results.select { |r| r[:warning] }

      if exceeded
        ServiceResponse.failure(error: "Budget exceeded for one or more periods")
      else
        ServiceResponse.success(
          data: {
            allowed: true,
            warnings: warnings,
            budgets: results
          }
        )
      end
    rescue => e
      ServiceResponse.failure(error: "Budget check failed: #{e.message}")
    end

    private

    def check_budget(budget)
      remaining = budget.remaining_cents
      projected = budget.spent_cents + @estimated_cost_cents

      {
        period_type: budget.period_type,
        limit_cents: budget.limit_cents,
        spent_cents: budget.spent_cents,
        remaining_cents: remaining,
        percentage_used: budget.percentage_used,
        exceeded: projected > budget.limit_cents,
        warning: budget.warning_threshold?
      }
    end
  end
end
