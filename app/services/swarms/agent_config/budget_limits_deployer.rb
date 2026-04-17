# frozen_string_literal: true

module Swarms
  module AgentConfig
    # Applies a budget_limits hash from a swarm agent definition to an Agent record.
    #
    # Called by AgentsDeployer after the agent record has been created or updated.
    # Handles two distinct budget storage mechanisms:
    #
    #   1. Column limits — daily_budget_limit / monthly_budget_limit on the agent row
    #   2. Period budgets — AgentBudget rows (one per period: daily/weekly/monthly)
    #
    # Period budget behaviour on import:
    #   - Existing AgentBudget rows for the agent are replaced (destroy + recreate)
    #     so the imported config is the authoritative source of truth.
    #   - This only runs when `periods` is present in the swarm data; if the key is
    #     absent the existing rows are left untouched.
    #
    # Usage:
    #   result = BudgetLimitsDeployer.call(agent: record, budget_limits: hash_or_nil)
    #   result.success?  # => true / false
    #   result.message   # => error string on failure
    class BudgetLimitsDeployer
      def self.call(agent:, budget_limits:)
        new(agent, budget_limits).call
      end

      def initialize(agent, budget_limits)
        @agent         = agent
        @budget_limits = budget_limits
      end

      def call
        return ServiceResponse.success(payload: { applied: false }) if @budget_limits.blank?

        validation = BudgetLimitsValidator.call(budget_limits: @budget_limits)
        return validation unless validation.success?

        b = @budget_limits.with_indifferent_access

        apply_column_limits(b)
        apply_period_budgets(b) if b.key?(:periods)

        ServiceResponse.success(payload: { applied: true })
      rescue ActiveRecord::RecordInvalid => e
        ServiceResponse.error(message: "Failed to apply budget limits: #{e.record.errors.full_messages.join(', ')}")
      end

      private

      def apply_column_limits(b)
        attrs = {}
        attrs[:daily_budget_limit]   = b[:daily_limit].to_d   if b.key?(:daily_limit)   && b[:daily_limit].present?
        attrs[:monthly_budget_limit] = b[:monthly_limit].to_d if b.key?(:monthly_limit) && b[:monthly_limit].present?
        @agent.update!(attrs) if attrs.any?
      end

      def apply_period_budgets(b)
        periods = Array(b[:periods])

        # Replace all existing period budgets for this agent atomically.
        @agent.agent_budgets.destroy_all

        periods.each do |entry|
          e = entry.with_indifferent_access
          @agent.agent_budgets.create!(
            period:      e[:period].to_s,
            limit_cents: e[:limit_cents].to_i,
            spent_cents: 0
          )
        end
      end
    end
  end
end
