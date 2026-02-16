# frozen_string_literal: true

class DashboardController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :index ]
  before_action :check_setup_complete

  def index
    @agents = Agent.visible.includes(:team).order(:name)
    @stats = platform_stats
    @cost_summary = calculate_cost_summary
    @recent_sessions = Session.includes(:agent)
                              .where("created_at > ?", 24.hours.ago)
                              .order(created_at: :desc)
                              .limit(10)
    @recent_tools = ToolExecution.includes(:tool, :agent)
                                 .where("created_at > ?", 24.hours.ago)
                                 .order(created_at: :desc)
                                 .limit(10)
  end

  private

  def check_setup_complete
    unless Setting.get("setup_complete") == "true"
      redirect_to setup_path
      return
    end

    authenticate_user! unless user_signed_in?
  end

  def platform_stats
    since = 24.hours.ago
    recent_usage = UsageRecord.where("created_at >= ?", since)

    {
      total_agents: Agent.visible.count,
      active_sessions: Session.where(status: :active).count,
      today_requests: recent_usage.count,
      today_tokens: recent_usage.sum(:input_tokens) + recent_usage.sum(:output_tokens),
      today_cost_cents: recent_usage.sum(:cost_cents),
      today_tool_calls: ToolExecution.where("created_at >= ?", since).count,
      total_sessions: Session.count,
      total_tokens: UsageRecord.sum(:input_tokens) + UsageRecord.sum(:output_tokens)
    }
  end

  def calculate_cost_summary
    since = 24.hours.ago

    Agent.visible.map do |agent|
      today_cents = UsageRecord.where(agent_id: agent.id)
                               .where("created_at >= ?", since)
                               .sum(:cost_cents)

      budget = agent.agent_budgets.find_by(period: "daily")
      daily_limit = budget&.limit_cents || 0

      {
        agent_id: agent.id,
        agent_name: agent.name,
        agent_role: agent.role,
        model: agent.llm_model,
        today_cost_dollars: today_cents / 100.0,
        budget_limit_dollars: daily_limit / 100.0,
        usage_percent: daily_limit.positive? ? (today_cents * 100.0 / daily_limit).round(1) : 0,
        today_tokens: UsageRecord.where(agent_id: agent.id)
                                 .where("created_at >= ?", since)
                                 .sum(:input_tokens) + UsageRecord.where(agent_id: agent.id)
                                                                   .where("created_at >= ?", since)
                                                                   .sum(:output_tokens)
      }
    end
  end
end
