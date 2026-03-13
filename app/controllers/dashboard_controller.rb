# frozen_string_literal: true

require "net/http"
require "socket"

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

    @providers = ProviderConfig.all.map do |p|
      status = check_provider(p)
      { config: p, status: status }
    end

    @db_connected = ActiveRecord::Base.connection.active? rescue false
    @redis_connected = begin
      Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379").ping == "PONG"
    rescue StandardError
      false
    end

    @services = detect_services

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

  def detect_services
    [
      { name: "Web Server", description: "HTTP & WebSocket", running: true, status: "Running" },
      { name: "Job Workers", description: "Background processing", running: sidekiq_running?, status: sidekiq_running? ? "Running" : "Down" },
      { name: "Database", description: "Primary data store", running: @db_connected, status: @db_connected ? "Healthy" : "Down" },
      { name: "Cache", description: "Jobs queue & real-time", running: @redis_connected, status: @redis_connected ? "Healthy" : "Down" },
      { name: "Browser", description: "Headless web automation", running: browser_running?, status: browser_running? ? "Running" : "Down" },
      { name: "Workspace", description: "Sandboxed execution", running: workspace_running?, status: workspace_running? ? "Running" : "Down" },
      { name: "Connector", description: "Messaging bridge", running: connector_running?, status: connector_running? ? "Running" : "Down" }
    ]
  rescue StandardError
    []
  end

  def sidekiq_running?
    Sidekiq::ProcessSet.new.size > 0
  rescue StandardError
    false
  end

  def browser_running?
    tcp_check("browser", 3001)
  end

  def workspace_running?
    File.directory?("/workspace")
  rescue StandardError
    false
  end

  def connector_running?
    tcp_check("connector", 3002)
  end

  def tcp_check(host, port, timeout = 2)
    Socket.tcp(host, port, connect_timeout: timeout) { true }
  rescue StandardError
    false
  end

  def check_provider(config)
    case config.adapter_type
    when "ollama"
      adapter = Providers::OllamaAdapter.new(config: config)
      result = adapter.models
      result.success? ? { ok: true, models: result.data[:models].size } : { ok: false }
    when "anthropic", "openai"
      { ok: config.enabled?, note: config.enabled? ? "Key configured" : "Disabled" }
    else
      { ok: false }
    end
  rescue StandardError
    { ok: false }
  end
end
