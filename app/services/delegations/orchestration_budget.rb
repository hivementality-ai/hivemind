# frozen_string_literal: true

module Delegations
  # Shared spend ceiling for one delegation tree. Every session in the tree
  # (the root plus all sub-agent sessions) carries the same orchestration_id
  # in its metadata; spend is the sum of their usage records. Unlike per-agent
  # budgets, this bounds the total cost of a single fan-out regardless of how
  # many agents it spreads across.
  class OrchestrationBudget
    def self.spent_cents(orchestration_id)
      UsageRecord.joins(:session)
                 .where("sessions.metadata->>'orchestration_id' = ?", orchestration_id)
                 .sum(:cost_cents)
    end

    def self.remaining_cents(orchestration_id)
      Config.orchestration_budget_cents - spent_cents(orchestration_id)
    end

    def self.exceeded?(orchestration_id)
      return false if orchestration_id.blank?

      remaining_cents(orchestration_id) <= 0
    end
  end
end
