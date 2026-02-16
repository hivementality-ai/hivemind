# frozen_string_literal: true

module Budgets
  # Record spending after LLM call
  class RecordSpend
    def self.call(agent:, cost_cents:, usage_metadata: {})
      new(agent: agent, cost_cents: cost_cents, usage_metadata: usage_metadata).call
    end

    def initialize(agent:, cost_cents:, usage_metadata: {})
      @agent = agent
      @cost_cents = cost_cents
      @usage_metadata = usage_metadata
    end

    def call
      ActiveRecord::Base.transaction do
        # Update all budget periods
        budgets = AgentBudget.where(agent: @agent)

        budgets.each do |budget|
          budget.increment!(:spent_cents, @cost_cents)

          # Check if exceeded or at warning threshold
          if budget.exceeded?
            handle_exceeded(budget)
          elsif budget.warning_threshold? && !budget.alert_sent?
            handle_warning(budget)
          end
        end

        # Create usage record
        usage_record = UsageRecord.create!(
          agent: @agent,
          cost_cents: @cost_cents,
          metadata: @usage_metadata,
          recorded_at: Time.current
        )

        # Broadcast budget update via ActionCable
        broadcast_update

        ServiceResponse.success(
          data: {
            recorded: true,
            usage_record: usage_record,
            budgets: budgets.map { |b| budget_summary(b) }
          }
        )
      end
    rescue => e
      ServiceResponse.failure(error: "Failed to record spend: #{e.message}")
    end

    private

    def handle_exceeded(budget)
      Rails.logger.warn "Agent #{@agent.id} exceeded #{budget.period_type} budget"

      # Send alert
      BudgetAlertJob.perform_async(@agent.id, budget.id, "exceeded")
    end

    def handle_warning(budget)
      Rails.logger.info "Agent #{@agent.id} at #{budget.percentage_used}% of #{budget.period_type} budget"
      BudgetAlertJob.perform_async(@agent.id, budget.id, "warning")
      # Note: alert_sent tracking can be added with a migration if needed
    end

    def broadcast_update
      ActionCable.server.broadcast(
        "budgets_channel",
        {
          type: "budget_update",
          agent_id: @agent.id,
          cost_cents: @cost_cents,
          timestamp: Time.current.iso8601
        }
      )
    end

    def budget_summary(budget)
      {
        period_type: budget.period_type,
        spent_cents: budget.spent_cents,
        limit_cents: budget.limit_cents,
        remaining_cents: budget.remaining_cents,
        percentage_used: budget.percentage_used,
        exceeded: budget.exceeded?
      }
    end
  end
end
