# frozen_string_literal: true

require "net/http"
require "socket"

class PlatformController < ApplicationController
  before_action :authenticate_user!

  def doctor
    @result = Hivemind::Doctor.run_all_as_hash
  end

  def status
    @stats = {
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
    @recent_usage = UsageRecord.order(created_at: :desc).limit(10).includes(:agent)

    # Cost stats
    @cost_today = UsageRecord.where(created_at: Time.current.beginning_of_day..).sum(:cost_cents) / 100.0
    @cost_week = UsageRecord.where(created_at: 1.week.ago..).sum(:cost_cents) / 100.0
    @cost_month = UsageRecord.where(created_at: Time.current.beginning_of_month..).sum(:cost_cents) / 100.0
    @tokens_today = UsageRecord.where(created_at: Time.current.beginning_of_day..).sum("input_tokens + output_tokens")
  end

  private

  def detect_services
    services = [
      { name: "Web Server", description: "HTTP & WebSocket", running: true, status: "Running" },
      { name: "Job Workers", description: "Background processing", running: sidekiq_running?, status: sidekiq_running? ? "Running" : "Down" },
      { name: "Database", description: "Primary data store", running: @db_connected, status: @db_connected ? "Healthy" : "Down" },
      { name: "Cache", description: "Jobs queue & real-time", running: @redis_connected, status: @redis_connected ? "Healthy" : "Down" },
      { name: "Browser", description: "Headless web automation", running: browser_running?, status: browser_running? ? "Running" : "Down" },
      { name: "Workspace", description: "Sandboxed execution", running: workspace_running?, status: workspace_running? ? "Running" : "Down" },
      { name: "Connector", description: "Messaging bridge", running: connector_running?, status: connector_running? ? "Running" : "Down" }
    ]
    services
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
