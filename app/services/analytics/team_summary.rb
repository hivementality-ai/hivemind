# frozen_string_literal: true

module Analytics
  # Compute team-level analytics
  class TeamSummary
    def self.call(team: nil, period: "week")
      new(team: team, period: period).call
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
      
      ServiceResponse.success(data: data)
    rescue => e
      ServiceResponse.failure(error: "Failed to compute team summary: #{e.message}")
    end
    
    private
    
    def date_range_for_period
      case @period
      when "day"
        1.day.ago..Time.current
      when "week"
        1.week.ago..Time.current
      when "month"
        1.month.ago..Time.current
      else
        1.week.ago..Time.current
      end
    end
    
    def compute_summary(agents)
      agent_ids = agents.pluck(:id)
      sessions = Session.where(agent_id: agent_ids, created_at: @date_range)
      usage = UsageRecord.where(agent_id: agent_ids, recorded_at: @date_range)
      
      {
        total_tasks: sessions.count,
        active_agents: agents.count,
        total_cost_cents: usage.sum(:cost_cents),
        total_cost_dollars: usage.sum(:cost_cents) / 100.0,
        avg_success_rate: compute_avg_success_rate(sessions)
      }
    end
    
    def compute_per_agent(agents)
      agents.map do |agent|
        summary = AgentSummary.call(agent: agent, period: @period)
        next unless summary.success?
        
        {
          agent: agent,
          tasks: summary.data[:tasks][:total],
          cost_cents: summary.data[:costs][:total_cents],
          success_rate: summary.data[:success_rate]
        }
      end.compact
    end
    
    def compute_avg_success_rate(sessions)
      return 0 if sessions.empty?
      
      completed = sessions.where(status: "completed").count
      ((completed.to_f / sessions.count) * 100).round(1)
    end
  end
end
