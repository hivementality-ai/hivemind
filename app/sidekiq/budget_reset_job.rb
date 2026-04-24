# frozen_string_literal: true

# Resets budgets on schedule (daily/weekly/monthly)
class BudgetResetJob
  include Sidekiq::Job

  def perform(period_type = "daily")
    Rails.logger.info "Resetting #{period_type} budgets..."

    budgets = AgentBudget.where(period: period_type)
                         .where("reset_at < ?", reset_cutoff_for(period_type))

    count = 0
    budgets.find_each do |budget|
      budget.reset!
      count += 1
    end

    Rails.logger.info "Reset #{count} #{period_type} budgets"

    Audit::Record.call(
      actor_type: "system",
      actor_id: "system",
      action: "budgets.reset",
      resource: nil,
      metadata: { period_type: period_type, count: count }
    )
  end

  private

  def reset_cutoff_for(period_type)
    case period_type
    when "daily"
      1.day.ago
    when "weekly"
      1.week.ago
    when "monthly"
      1.month.ago
    else
      1.day.ago
    end
  end
end
