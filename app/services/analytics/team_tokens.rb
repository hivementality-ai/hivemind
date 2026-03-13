# frozen_string_literal: true

module Analytics
  class TeamTokens
    def self.call(period: "week")
      new(period:).call
    end

    def initialize(period: "week")
      @period = period
      @date_range = date_range_for_period
    end

    def call
      teams = Team.includes(agents: :usage_records).all
      sdk_proxy_active = sdk_proxy_active?

      team_data = teams.map { |team| build_team_stats(team, sdk_proxy_active) }
      unassigned = build_unassigned_stats(sdk_proxy_active)

      summary = build_summary(team_data, unassigned)

      ServiceResponse.success(data: {
        period: @period,
        date_range: @date_range,
        sdk_proxy_active: sdk_proxy_active,
        summary: summary,
        teams: team_data,
        unassigned: unassigned
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Failed to compute team tokens: #{e.message}")
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

    def build_team_stats(team, sdk_proxy_active)
      agent_ids = team.agents.pluck(:id)
      usage = UsageRecord.where(agent_id: agent_ids, created_at: @date_range)

      input_tokens = usage.sum(:input_tokens)
      output_tokens = usage.sum(:output_tokens)
      raw_cost_cents = usage.sum(:cost_cents)

      {
        team_id: team.id,
        team_name: team.name,
        agent_count: team.agents.count,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        total_tokens: input_tokens + output_tokens,
        cost_cents: sdk_proxy_active ? 0 : raw_cost_cents,
        cost_dollars: sdk_proxy_active ? 0.0 : (raw_cost_cents / 100.0),
        requests: usage.count,
        models_used: usage.distinct.pluck(:llm_model).compact,
        sdk_proxy: sdk_proxy_active
      }
    end

    def build_unassigned_stats(sdk_proxy_active)
      agent_ids = Agent.where(team_id: nil).pluck(:id)
      return nil if agent_ids.empty?

      usage = UsageRecord.where(agent_id: agent_ids, created_at: @date_range)
      input_tokens = usage.sum(:input_tokens)
      output_tokens = usage.sum(:output_tokens)
      raw_cost_cents = usage.sum(:cost_cents)

      {
        team_name: "Unassigned",
        agent_count: agent_ids.size,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        total_tokens: input_tokens + output_tokens,
        cost_cents: sdk_proxy_active ? 0 : raw_cost_cents,
        cost_dollars: sdk_proxy_active ? 0.0 : (raw_cost_cents / 100.0),
        requests: usage.count,
        models_used: usage.distinct.pluck(:llm_model).compact,
        sdk_proxy: sdk_proxy_active
      }
    end

    def build_summary(team_data, unassigned)
      all_entries = team_data + [unassigned].compact

      {
        total_input_tokens: all_entries.sum { |e| e[:input_tokens] },
        total_output_tokens: all_entries.sum { |e| e[:output_tokens] },
        total_tokens: all_entries.sum { |e| e[:total_tokens] },
        total_cost_cents: all_entries.sum { |e| e[:cost_cents] },
        total_cost_dollars: all_entries.sum { |e| e[:cost_dollars] },
        total_requests: all_entries.sum { |e| e[:requests] },
        team_count: team_data.size,
        sdk_proxy_active: all_entries.any? { |e| e[:sdk_proxy] }
      }
    end

    def sdk_proxy_active?
      anthropic_config = ProviderConfig.find_by(adapter_type: "anthropic", enabled: true)
      return false unless anthropic_config

      api_key = anthropic_config.api_key
      api_key.present? && api_key.start_with?("sk-ant-oat")
    end
  end
end
