# frozen_string_literal: true

module Analytics
  # Compute agent analytics summary
  class AgentSummary
    def self.call(agent:, period: "week")
      new(agent: agent, period: period).call
    end
    
    def initialize(agent:, period: "week")
      @agent = agent
      @period = period
      @date_range = date_range_for_period
    end
    
    def call
      data = {
        agent: @agent,
        period: @period,
        date_range: @date_range,
        tasks: task_stats,
        tokens: token_stats,
        costs: cost_stats,
        tools: tool_stats,
        success_rate: success_rate,
        avg_response_time: avg_response_time
      }
      
      ServiceResponse.success(data: data)
    rescue => e
      ServiceResponse.failure(error: "Failed to compute agent summary: #{e.message}")
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
    
    def task_stats
      sessions = @agent.sessions.where(created_at: @date_range)
      
      {
        total: sessions.count,
        completed: sessions.where(status: "completed").count,
        active: sessions.where(status: "active").count,
        failed: sessions.where(status: "failed").count
      }
    end
    
    def token_stats
      usage = UsageRecord.where(agent: @agent, recorded_at: @date_range)
      
      {
        total_input: usage.sum("metadata->>'input_tokens'"),
        total_output: usage.sum("metadata->>'output_tokens'"),
        by_model: usage.group("metadata->>'model'").count
      }
    end
    
    def cost_stats
      usage = UsageRecord.where(agent: @agent, recorded_at: @date_range)
      total_cents = usage.sum(:cost_cents)
      
      # Cost breakdown by day
      by_day = usage.group_by_day(:recorded_at, time_zone: "UTC")
                   .sum(:cost_cents)
      
      {
        total_cents: total_cents,
        total_dollars: total_cents / 100.0,
        by_day: by_day.transform_values { |cents| cents / 100.0 },
        avg_per_request: usage.any? ? (total_cents / usage.count.to_f) : 0
      }
    end
    
    def tool_stats
      # Extract tool calls from session transcripts
      sessions = @agent.sessions.where(created_at: @date_range)
      tool_calls = []
      
      sessions.find_each do |session|
        next unless session.transcript.is_a?(Array)
        
        session.transcript.each do |entry|
          if entry.is_a?(Hash) && entry["tool_calls"]
            entry["tool_calls"].each do |call|
              tool_calls << call["function"]["name"] if call["function"]
            end
          end
        end
      end
      
      # Count tool usage
      counts = tool_calls.group_by(&:itself).transform_values(&:count)
      sorted = counts.sort_by { |_, count| -count }.first(10)
      
      {
        total_calls: tool_calls.size,
        most_used: sorted.to_h
      }
    end
    
    def success_rate
      sessions = @agent.sessions.where(created_at: @date_range)
      return 0 if sessions.empty?
      
      completed = sessions.where(status: "completed").count
      ((completed.to_f / sessions.count) * 100).round(1)
    end
    
    def avg_response_time
      sessions = @agent.sessions
                      .where(created_at: @date_range)
                      .where.not(completed_at: nil)
      
      return 0 if sessions.empty?
      
      total_seconds = sessions.sum do |session|
        (session.completed_at - session.created_at).to_i
      end
      
      (total_seconds.to_f / sessions.count).round(1)
    end
  end
end
