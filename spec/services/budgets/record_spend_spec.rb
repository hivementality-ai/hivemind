# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budgets::RecordSpend do
  let(:agent) { create(:agent, model_provider: "anthropic", llm_model: "claude-3-5-sonnet") }
  let(:session) { create(:session, agent: agent) }

  before do
    allow(BudgetAlertJob).to receive(:perform_async)
    allow(ActionCable.server).to receive(:broadcast)
    allow(WebhookEmitter).to receive(:emit)
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

    context "webhook threshold alerts" do
      let!(:budget) { create(:agent_budget, agent: agent, limit_cents: 10_000, spent_cents: 0) }

      context "crossing 80% for the first time" do
        before { budget.update!(spent_cents: 7_900) }

        it "emits budget.threshold webhook at 80" do
          result  # pushes to 8000 = 80%
          expect(WebhookEmitter).to have_received(:emit).with(
            "budget.threshold",
            hash_including(threshold: 80, agent_id: agent.id),
            agent: agent
          )
        end

        it "stores 80 as last_alerted_threshold" do
          result
          expect(budget.reload.last_alerted_threshold).to eq(80)
        end
      end

      context "already alerted at 80%, crossing again" do
        before { budget.update!(spent_cents: 7_900, last_alerted_threshold: 80) }

        it "does not re-emit the 80% webhook" do
          result
          expect(WebhookEmitter).not_to have_received(:emit).with(
            "budget.threshold",
            hash_including(threshold: 80),
            anything
          )
        end
      end

      context "crossing 100% for the first time" do
        before { budget.update!(spent_cents: 9_950) }

        it "emits budget.threshold webhook at 100" do
          result  # pushes to 10050 >= 10000
          expect(WebhookEmitter).to have_received(:emit).with(
            "budget.threshold",
            hash_including(threshold: 100, agent_id: agent.id),
            agent: agent
          )
        end

        it "stores 100 as last_alerted_threshold" do
          result
          expect(budget.reload.last_alerted_threshold).to eq(100)
        end
      end

      context "already alerted at 100%" do
        before { budget.update!(spent_cents: 9_950, last_alerted_threshold: 100) }

        it "does not re-emit the 100% webhook" do
          result
          expect(WebhookEmitter).not_to have_received(:emit).with(
            "budget.threshold",
            hash_including(threshold: 100),
            anything
          )
        end
      end

      context "80% then 100% sequence" do
        it "fires 80 alert then 100 alert exactly once each" do
          budget.update!(spent_cents: 7_900)
          described_class.call(agent: agent, cost_cents: 100, provider: "anthropic",
                               llm_model: "claude-3-5-sonnet")
          expect(budget.reload.last_alerted_threshold).to eq(80)

          budget.update!(spent_cents: 9_950)
          described_class.call(agent: agent, cost_cents: 100, provider: "anthropic",
                               llm_model: "claude-3-5-sonnet")
          expect(budget.reload.last_alerted_threshold).to eq(100)

          expect(WebhookEmitter).to have_received(:emit).with("budget.threshold",
            hash_including(threshold: 80), anything).once
          expect(WebhookEmitter).to have_received(:emit).with("budget.threshold",
            hash_including(threshold: 100), anything).once
        end
      end
    end
  end
end
