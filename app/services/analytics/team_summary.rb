# frozen_string_literal: true

module Analytics
  class TeamSummary
    def self.call(team: nil, period: "week")
      new(team:, period:).call
    end

    def initialize(team: nil, period: "week")
      @team = team
      @period = period
      @date_range = date_range_for_period
    end

    def call
      agents = @team ? @team.agents : Agent.all

      data = {
        team: @team,
        period: @period,
        date_range: @date_range,
        agents: agents,
        summary: compute_summary(agents),
        per_agent: compute_per_agent(agents)
      }

      ServiceResponse.success(data:)
    rescue StandardError => e
      ServiceResponse.failure(error: "Failed to compute team summary: #{e.message}")
    end

    private

    def date_range_for_period
      case @period
      when "day" then Time.current.beginning_of_day..Time.current
      when "week" then Time.current.beginning_of_week..Time.current
      when "month" then Time.current.beginning_of_month..Time.current
      else Time.current.beginning_of_week..Time.current
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
      agents.map do |agent|
        usage = agent.usage_records.where(created_at: @date_range)
        sessions = agent.sessions.where(created_at: @date_range)
        cost = usage.sum(:cost_cents)

        {
          agent: agent,
          sessions: sessions.count,
          requests: usage.count,
          cost_cents: cost,
          input_tokens: usage.sum(:input_tokens),
          output_tokens: usage.sum(:output_tokens),
          models_used: usage.distinct.pluck(:llm_model).compact
        }
      end.sort_by { |s| -s[:cost_cents] }
    end
  end
end
