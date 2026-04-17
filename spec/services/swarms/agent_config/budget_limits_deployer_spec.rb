# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::AgentConfig::BudgetLimitsDeployer do
  def call(agent:, budget_limits:)
    described_class.call(agent: agent, budget_limits: budget_limits)
  end

  describe "nil / blank budget_limits" do
    it "is a no-op and succeeds" do
      agent = create(:agent, name: "Mando", role: "Engineer")
      result = call(agent: agent, budget_limits: nil)
      expect(result).to be_success
      expect(result.payload[:applied]).to be false
    end

    it "leaves existing column limits unchanged" do
      agent = create(:agent, name: "Mando", role: "Engineer",
        daily_budget_limit: 50.0, monthly_budget_limit: 500.0)
      call(agent: agent, budget_limits: nil)
      expect(agent.reload.daily_budget_limit.to_f).to eq(50.0)
      expect(agent.reload.monthly_budget_limit.to_f).to eq(500.0)
    end
  end

  describe "column limits" do
    it "sets daily_budget_limit when provided" do
      agent = create(:agent, name: "Mando", role: "Engineer")
      call(agent: agent, budget_limits: { "daily_limit" => 25.0 })
      expect(agent.reload.daily_budget_limit.to_f).to eq(25.0)
    end

    it "sets monthly_budget_limit when provided" do
      agent = create(:agent, name: "Mando", role: "Engineer")
      call(agent: agent, budget_limits: { "monthly_limit" => 250.0 })
      expect(agent.reload.monthly_budget_limit.to_f).to eq(250.0)
    end

    it "sets both limits together" do
      agent = create(:agent, name: "Mando", role: "Engineer")
      result = call(agent: agent, budget_limits: { "daily_limit" => 15.0, "monthly_limit" => 150.0 })
      expect(result).to be_success
      expect(agent.reload.daily_budget_limit.to_f).to eq(15.0)
      expect(agent.reload.monthly_budget_limit.to_f).to eq(150.0)
    end
  end

  describe "period budgets" do
    it "creates AgentBudget rows from periods" do
      agent = create(:agent, name: "Mando", role: "Engineer")
      budget_limits = {
        "periods" => [
          { "period" => "daily",   "limit_cents" => 1000 },
          { "period" => "monthly", "limit_cents" => 20000 }
        ]
      }

      expect { call(agent: agent, budget_limits: budget_limits) }
        .to change { agent.agent_budgets.count }.from(0).to(2)
    end

    it "stores correct period and limit_cents on each row" do
      agent = create(:agent, name: "Mando", role: "Engineer")
      call(agent: agent, budget_limits: {
        "periods" => [{ "period" => "weekly", "limit_cents" => 5000 }]
      })

      budget = agent.agent_budgets.first
      expect(budget.period).to eq("weekly")
      expect(budget.limit_cents.to_i).to eq(5000)
      expect(budget.spent_cents.to_i).to eq(0)
    end

    it "replaces existing AgentBudget rows on overwrite" do
      agent = create(:agent, name: "Mando", role: "Engineer")
      agent.agent_budgets.create!(period: "daily", limit_cents: 500, spent_cents: 0)

      call(agent: agent, budget_limits: {
        "periods" => [{ "period" => "monthly", "limit_cents" => 10000 }]
      })

      expect(agent.agent_budgets.count).to eq(1)
      expect(agent.agent_budgets.first.period).to eq("monthly")
    end

    it "does not touch AgentBudget rows when periods key is absent" do
      agent = create(:agent, name: "Mando", role: "Engineer")
      agent.agent_budgets.create!(period: "daily", limit_cents: 500, spent_cents: 0)

      call(agent: agent, budget_limits: { "daily_limit" => 20.0 })

      expect(agent.agent_budgets.count).to eq(1)
    end
  end

  describe "invalid budget_limits" do
    it "returns an error without updating the agent" do
      agent = create(:agent, name: "Mando", role: "Engineer",
        daily_budget_limit: 10.0)
      result = call(agent: agent, budget_limits: { "daily_limit" => -5.0 })

      expect(result).to be_error
      expect(result.message).to match(/positive number/)
      expect(agent.reload.daily_budget_limit.to_f).to eq(10.0)
    end
  end
end
