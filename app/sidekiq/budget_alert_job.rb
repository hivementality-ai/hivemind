# frozen_string_literal: true

# Sends alerts when agents hit budget thresholds
class BudgetAlertJob
  include Sidekiq::Job

  def perform(agent_id, budget_id, alert_type)
    agent = Agent.find(agent_id)
    budget = AgentBudget.find(budget_id)

    message = case alert_type
    when "warning"
                "⚠️ Agent '#{agent.name}' has used #{budget.percentage_used}% of its #{budget.period_type} budget"
    when "exceeded"
                "🚫 Agent '#{agent.name}' has EXCEEDED its #{budget.period_type} budget"
    else
                "Budget alert for agent '#{agent.name}'"
    end

    Rails.logger.warn message

    # Broadcast via ActionCable
    ActionCable.server.broadcast(
      "notifications_channel",
      {
        type: "budget_alert",
        severity: alert_type == "exceeded" ? "error" : "warning",
        message: message,
        agent_id: agent.id,
        budget_id: budget.id
      }
    )

    # Could also send email, Slack notification, etc.

    Audit::Log.call(
      actor: "system",
      action: "budget.alert_sent",
      resource: agent,
      metadata: {
        budget_id: budget.id,
        alert_type: alert_type,
        percentage_used: budget.percentage_used
      }
    )
  end
end
