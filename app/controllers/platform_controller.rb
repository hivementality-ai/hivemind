# frozen_string_literal: true

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

    @recent_usage = UsageRecord.order(created_at: :desc).limit(10).includes(:agent)

    @cost_today = UsageRecord.where(created_at: Time.current.beginning_of_day..).sum(:cost_cents) / 100.0
    @cost_week = UsageRecord.where(created_at: 1.week.ago..).sum(:cost_cents) / 100.0
    @cost_month = UsageRecord.where(created_at: Time.current.beginning_of_month..).sum(:cost_cents) / 100.0
    @tokens_today = UsageRecord.where(created_at: Time.current.beginning_of_day..).sum("input_tokens + output_tokens")
  end
end
