# frozen_string_literal: true

module Analytics
  class TeamSummary
    def self.call(team: nil, period: "week", days: nil)
      new(team:, period:, days:).call
    end

    def initialize(team: nil, period: "week", days: nil)
      @team = team
      @period = period
      @days = days&.to_i
      @date_range = date_range_for_period
    end

    def call
      agents = @team ? @team.agents : Agent.all

      data = {
        team: @team,
        period: @period,
        days: @days,
        date_range: @date_range,
        agents: agents,
        summary: compute_summary(agents),
        per_agent: compute_per_agent(agents),
        daily_trend: compute_daily_trend(agents)
      }

      ServiceResponse.success(data:)
    rescue StandardError => e
      ServiceResponse.failure(error: "Failed to compute team summary: #{e.message}")
    end

    private

    def date_range_for_period
      if @days
        @days.days.ago.beginning_of_day..Time.current
      else
        case @period
        when "day" then Time.current.beginning_of_day..Time.current
        when "week" then Time.current.beginning_of_week..Time.current
        when "month" then Time.current.beginning_of_month..Time.current
        else Time.current.beginning_of_week..Time.current
        end
      end
    end

    def compute_summary(agents)
      agent_ids = agents.pluck(:id)
      sessions = Session.where(agent_id: agent_ids, created_at: @date_range)
      usage = UsageRecord.where(agent_id: agent_ids, created_at: @date_range)

      total_cost = usage.sum(:cost_cents)
      total_input = usage.sum(:input_tokens)
      total_output = usage.sum(:output_tokens)

      {
        total_sessions: sessions.count,
        active_agents: agents.where(enabled: true).count,
        total_cost_cents: total_cost,
        total_cost_dollars: total_cost / 100.0,
        total_input_tokens: total_input,
        total_output_tokens: total_output,
        total_tokens: total_input + total_output,
        total_requests: usage.count,
        avg_cost_per_request: usage.any? ? (total_cost / usage.count.to_f / 100.0).round(6) : 0
      }
    end

    def compute_per_agent(agents)
      agent_ids = agents.pluck(:id)
      # Batch error-rate queries to avoid N+1
      all_exec = ToolExecution.where(agent_id: agent_ids, created_at: @date_range)
      total_by_agent  = all_exec.group(:agent_id).count
      failed_by_agent = all_exec.where.not(status: "completed").group(:agent_id).count

      agents.map do |agent|
        usage = agent.usage_records.where(created_at: @date_range)
        sessions = agent.sessions.where(created_at: @date_range)
        cost = usage.sum(:cost_cents)

        total_exec  = total_by_agent[agent.id].to_i
        failed_exec = failed_by_agent[agent.id].to_i
        error_rate  = total_exec > 0 ? (failed_exec * 100.0 / total_exec).round(1) : nil

        {
          agent: agent,
          sessions: sessions.count,
          requests: usage.count,
          cost_cents: cost,
          input_tokens: usage.sum(:input_tokens),
          output_tokens: usage.sum(:output_tokens),
          models_used: usage.distinct.pluck(:llm_model).compact,
          error_rate: error_rate,
          total_executions: total_exec
        }
      end.sort_by { |s| -s[:cost_cents] }
    end

    def compute_daily_trend(agents)
      agent_ids = agents.pluck(:id)
      usage = UsageRecord.where(agent_id: agent_ids, created_at: @date_range)

      usage.group_by { |r| r.created_at.to_date }.transform_values do |records|
        {
          cost_cents: records.sum(&:cost_cents),
          total_tokens: records.sum { |r| r.input_tokens + r.output_tokens },
          requests: records.size
        }
      end.sort.to_h
    end
  end
end
