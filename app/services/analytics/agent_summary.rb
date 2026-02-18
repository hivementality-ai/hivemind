# frozen_string_literal: true

module Analytics
  class AgentSummary
    def self.call(agent:, period: "week")
      new(agent:, period:).call
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
        sessions: session_stats,
        tokens: token_stats,
        costs: cost_stats,
        tools: tool_stats,
        models: model_stats,
        daily_usage: daily_usage
      }

      ServiceResponse.success(data:)
    rescue StandardError => e
      ServiceResponse.failure(error: "Failed to compute agent summary: #{e.message}")
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

    def usage
      @usage ||= @agent.usage_records.where(created_at: @date_range)
    end

    def sessions
      @sessions ||= @agent.sessions.where(created_at: @date_range)
    end

    def session_stats
      {
        total: sessions.count,
        active: sessions.where(status: :active).count,
        completed: sessions.where(status: :completed).count,
        messages: sessions.sum { |s| (s.transcript || []).size }
      }
    end

    def token_stats
      {
        input: usage.sum(:input_tokens),
        output: usage.sum(:output_tokens),
        total: usage.sum(:input_tokens) + usage.sum(:output_tokens)
      }
    end

    def cost_stats
      total = usage.sum(:cost_cents)
      {
        total_cents: total,
        total_dollars: total / 100.0,
        avg_per_request: usage.any? ? (total / usage.count.to_f / 100.0).round(6) : 0
      }
    end

    def tool_stats
      executions = @agent.tool_executions.where(created_at: @date_range)
      by_tool = executions.joins(:tool).group("tools.name").count
      success_count = executions.where(success: true).count

      {
        total: executions.count,
        success_rate: executions.any? ? (success_count * 100.0 / executions.count).round(1) : 0,
        by_tool: by_tool.sort_by { |_, v| -v }.to_h
      }
    end

    def model_stats
      usage.group(:llm_model).count.sort_by { |_, v| -v }.to_h
    end

    def daily_usage
      # Group by date for the chart
      usage.group_by { |r| r.created_at.to_date }.transform_values do |records|
        {
          requests: records.size,
          cost_cents: records.sum(&:cost_cents),
          input_tokens: records.sum(&:input_tokens),
          output_tokens: records.sum(&:output_tokens)
        }
      end.sort.to_h
    end
  end
end
