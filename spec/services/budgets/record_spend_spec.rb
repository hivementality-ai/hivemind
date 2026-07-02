# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budgets::RecordSpend do
  let(:agent) { create(:agent, model_provider: "anthropic", llm_model: "claude-3-5-sonnet") }
  let(:session) { create(:session, agent: agent) }

  before do
    allow(BudgetAlertJob).to receive(:perform_async)
    allow(ActionCable.server).to receive(:broadcast)
  end

  describe ".call" do
    subject(:result) do
      described_class.call(
        agent: agent,
        cost_cents: 100,
        session: session,
        provider: "anthropic",
        llm_model: "claude-3-5-sonnet",
        input_tokens: 200,
        output_tokens: 50
      )
    end

    context "usage record creation" do
      it "creates a UsageRecord" do
        expect { result }.to change(UsageRecord, :count).by(1)
      end

      it "stores all fields on the UsageRecord" do
        result
        record = UsageRecord.last
        expect(record.cost_cents).to eq(100)
        expect(record.provider).to eq("anthropic")
        expect(record.llm_model).to eq("claude-3-5-sonnet")
        expect(record.input_tokens).to eq(200)
        expect(record.output_tokens).to eq(50)
        expect(record.session).to eq(session)
      end

      it "returns success" do
        expect(result.success?).to be true
      end
    end

    context "budget spend recording" do
      context "when agent has no budgets" do
        it "still creates the UsageRecord" do
          expect { result }.to change(UsageRecord, :count).by(1)
        end

        it "returns success" do
          expect(result.success?).to be true
        end
      end

      context "when agent has active budgets" do
        let!(:daily_budget) { create(:agent_budget, :daily, agent: agent, spent_cents: 0, limit_cents: 10_000) }

        it "increments the budget's spent_cents" do
          expect { result }.to change { daily_budget.reload.spent_cents }.by(100)
        end

        it "increments multiple budget periods" do
          monthly_budget = create(:agent_budget, :monthly, agent: agent, spent_cents: 0, limit_cents: 100_000)
          result
          expect(daily_budget.reload.spent_cents).to eq(100)
          expect(monthly_budget.reload.spent_cents).to eq(100)
        end
      end

      context "when spend pushes budget over the limit" do
        let!(:budget) { create(:agent_budget, agent: agent, spent_cents: 9_950, limit_cents: 10_000) }

        it "fires a BudgetAlertJob with 'exceeded'" do
          result
          expect(BudgetAlertJob).to have_received(:perform_async).with(agent.id, budget.id, "exceeded")
        end
      end

      context "when spend reaches warning threshold" do
        let!(:budget) { create(:agent_budget, agent: agent, spent_cents: 7_900, limit_cents: 10_000) }

        it "fires a BudgetAlertJob with 'warning'" do
          result  # 7900 + 100 = 8000, which is 80% of 10000 => warning
          expect(BudgetAlertJob).to have_received(:perform_async).with(agent.id, budget.id, "warning")
        end
      end
    end
  end
end
