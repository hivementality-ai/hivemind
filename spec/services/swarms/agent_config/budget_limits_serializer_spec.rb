# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::AgentConfig::BudgetLimitsSerializer do
  def call(agent)
    described_class.call(agent: agent)
  end

  describe "all defaults, no period budgets" do
    it "returns nil when limits are platform defaults and no agent_budgets exist" do
      # Platform defaults: daily=10.0, monthly=100.0
      agent = create(:agent, name: "Mando", role: "Engineer",
        daily_budget_limit: 10.0, monthly_budget_limit: 100.0)
      expect(call(agent)).to be_nil
    end
  end

  describe "column limits" do
    it "includes daily_limit when it differs from the default" do
      agent = create(:agent, name: "Mando", role: "Engineer",
        daily_budget_limit: 25.0, monthly_budget_limit: 100.0)
      result = call(agent)
      expect(result).not_to be_nil
      expect(result["daily_limit"]).to eq(25.0)
      expect(result).not_to have_key("monthly_limit")
    end

    it "includes monthly_limit when it differs from the default" do
      agent = create(:agent, name: "Mando", role: "Engineer",
        daily_budget_limit: 10.0, monthly_budget_limit: 500.0)
      result = call(agent)
      expect(result["monthly_limit"]).to eq(500.0)
      expect(result).not_to have_key("daily_limit")
    end

    it "includes both limits when both differ from defaults" do
      agent = create(:agent, name: "Mando", role: "Engineer",
        daily_budget_limit: 20.0, monthly_budget_limit: 200.0)
      result = call(agent)
      expect(result["daily_limit"]).to eq(20.0)
      expect(result["monthly_limit"]).to eq(200.0)
    end
  end

  describe "period budgets" do
    it "includes periods when AgentBudget rows exist" do
      agent = create(:agent, name: "Mando", role: "Engineer")
      agent.agent_budgets.create!(period: "daily",   limit_cents: 1000, spent_cents: 0)
      agent.agent_budgets.create!(period: "monthly", limit_cents: 20000, spent_cents: 500)

      result = call(agent)
      expect(result["periods"]).to match_array([
        { "period" => "daily",   "limit_cents" => 1000 },
        { "period" => "monthly", "limit_cents" => 20000 }
      ])
    end

    it "omits periods key when no AgentBudget rows exist" do
      agent = create(:agent, name: "Mando", role: "Engineer",
        daily_budget_limit: 20.0)
      result = call(agent)
      expect(result).not_to have_key("periods")
    end

    it "serializes spent_cents without including it in export" do
      agent = create(:agent, name: "Mando", role: "Engineer")
      agent.agent_budgets.create!(period: "weekly", limit_cents: 5000, spent_cents: 1234)

      result = call(agent)
      period_entry = result["periods"].first
      expect(period_entry).not_to have_key("spent_cents")
      expect(period_entry["limit_cents"]).to eq(5000)
    end
  end

  describe "combined output" do
    it "returns a hash with both column limits and periods" do
      agent = create(:agent, name: "Mando", role: "Engineer",
        daily_budget_limit: 30.0, monthly_budget_limit: 100.0)
      agent.agent_budgets.create!(period: "daily", limit_cents: 3000, spent_cents: 0)

      result = call(agent)
      expect(result["daily_limit"]).to eq(30.0)
      expect(result["periods"].size).to eq(1)
    end
  end
end
