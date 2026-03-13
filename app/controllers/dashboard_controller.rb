# frozen_string_literal: true

class DashboardController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :index ]
  before_action :check_setup_complete

  ALLOWED_TABS = %w[overview usage health].freeze

  def index
    @tab = ALLOWED_TABS.include?(params[:tab]) ? params[:tab] : "overview"

    case @tab
    when "overview"
      load_overview_data
    when "usage"
      load_usage_data
    when "health"
      load_health_data
    end
  end

  private

  def check_setup_complete
    unless Setting.get("setup_complete") == "true"
      redirect_to setup_path
      return
    end

    authenticate_user! unless user_signed_in?
  end

  # === Overview Tab ===

  def load_overview_data
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

  # === Usage Tab (from Analytics) ===

  def load_usage_data
    @period = params[:period] || "week"

    # Team summary
    response = Analytics::TeamSummary.call(period: @period)
    if response.success?
      @summary = response.data[:summary]
      @per_agent = response.data[:per_agent]
    else
      @summary = {}
      @per_agent = []
    end

    # Team tokens breakdown
    tokens_response = Analytics::TeamTokens.call(period: @period)
    if tokens_response.success?
      @team_tokens = tokens_response.data
    else
      @team_tokens = nil
    end
  end

  # === Health Tab (from Platform) ===

  def load_health_data
    @health_stats = {
      agents: Agent.count,
      agents_enabled: Agent.enabled.count,
      teams: Team.count,
      sessions: Session.count,
      team_chats: TeamChatSession.count,
      team_messages: TeamChatMessage.count,
      usage_records: UsageRecord.count,
      memories: MemoryEntry.count,
      tool_executions: ToolExecution.count,
      tools: Tool.count
    }

    health = Platform::ServiceHealth.call
    if health.success?
      @providers = health.data[:providers]
      @db_connected = health.data[:db_connected]
      @redis_connected = health.data[:redis_connected]
      @services = health.data[:services]
    else
      @providers = []
      @db_connected = false
      @redis_connected = false
      @services = []
    end

    @cost_today = UsageRecord.where(created_at: Time.current.beginning_of_day..).sum(:cost_cents) / 100.0
    @cost_week = UsageRecord.where(created_at: 1.week.ago..).sum(:cost_cents) / 100.0
    @cost_month = UsageRecord.where(created_at: Time.current.beginning_of_month..).sum(:cost_cents) / 100.0
    @tokens_today = UsageRecord.where(created_at: Time.current.beginning_of_day..).sum("input_tokens + output_tokens")
  end

  # === Shared helpers ===

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
