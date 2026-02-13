# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    @agents = Agent.includes(:team)
                   .order(:name)
                   .select(:id, :name, :role, :status, :current_task, :team_id)

    @recent_activity = fetch_recent_activity
    @cost_summary = calculate_cost_summary
  end

  private

  def fetch_recent_activity
    # Combine recent tool calls, messages, and delegations
    recent_sessions = Session.includes(:agent)
                             .where("created_at > ?", 24.hours.ago)
                             .order(created_at: :desc)
                             .limit(50)

    recent_messages = TeamMessage.includes(:from_agent, :to_agent)
                                 .where("created_at > ?", 24.hours.ago)
                                 .order(created_at: :desc)
                                 .limit(50)

    # Merge and sort by timestamp
    (recent_sessions + recent_messages).sort_by { |item| 
      item.try(:created_at) || Time.at(0) 
    }.reverse.take(20)
  end

  def calculate_cost_summary
    today_start = Time.current.beginning_of_day

    Agent.all.map do |agent|
      usage = UsageRecord.where(agent_id: agent.id)
                        .where("created_at >= ?", today_start)
                        .sum(:cost)

      {
        agent_id: agent.id,
        agent_name: agent.name,
        today_cost: usage,
        budget_limit: agent.daily_budget_limit,
        usage_percent: agent.daily_budget_limit.positive? ? (usage / agent.daily_budget_limit * 100).round(2) : 0
      }
    end
  end
end
