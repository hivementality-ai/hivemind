# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Budgets::RecordSpend do
  describe '.call' do
    let(:agent) { create(:agent) }
    let(:cost_cents) { 150 }
    let(:usage_metadata) do
      {
        input_tokens: 100,
        output_tokens: 50,
        llm_model: "gpt-4",
        session_id: 123
      }
    end

    before do
      # Mock ActionCable
      allow(ActionCable.server).to receive(:broadcast)
      # Mock Sidekiq jobs
      allow(BudgetAlertJob).to receive(:perform_async)
    end

    describe 'when no budgets exist' do
      it 'creates usage record without updating budgets' do
        expect {
          described_class.call(
            agent: agent,
            cost_cents: cost_cents,
            usage_metadata: usage_metadata
          )
        }.to change(UsageRecord, :count).by(1)

        usage_record = UsageRecord.last
        expect(usage_record.agent).to eq(agent)
        expect(usage_record.cost_cents).to eq(cost_cents)
        expect(usage_record.metadata).to eq(usage_metadata.stringify_keys)
        expect(usage_record.recorded_at).to be_present
      end

      it 'returns success with empty budgets array' do
        result = described_class.call(
          agent: agent,
          cost_cents: cost_cents,
          usage_metadata: usage_metadata
        )

        expect(result).to be_a(ServiceResponse)
        expect(result.success?).to be true
        expect(result.data[:recorded]).to be true
        expect(result.data[:usage_record]).to be_a(UsageRecord)
        expect(result.data[:budgets]).to eq([])
      end
    end

    describe 'with existing budgets' do
      let!(:daily_budget) { create(:agent_budget, agent: agent, period_type: 'daily', limit_cents: 1000, spent_cents: 300) }
      let!(:monthly_budget) { create(:agent_budget, agent: agent, period_type: 'monthly', limit_cents: 5000, spent_cents: 2000) }

      before do
        # Mock budget methods
        allow(daily_budget).to receive(:exceeded?).and_return(false)
        allow(daily_budget).to receive(:warning_threshold?).and_return(false)
        allow(daily_budget).to receive(:remaining_cents).and_return(550) # After increment
        allow(daily_budget).to receive(:percentage_used).and_return(45.0)

        allow(monthly_budget).to receive(:exceeded?).and_return(false)
        allow(monthly_budget).to receive(:warning_threshold?).and_return(false)
        allow(monthly_budget).to receive(:remaining_cents).and_return(2850) # After increment
        allow(monthly_budget).to receive(:percentage_used).and_return(43.0)
      end

      it 'updates all budget periods' do
        described_class.call(
          agent: agent,
          cost_cents: cost_cents,
          usage_metadata: usage_metadata
        )

        expect(daily_budget).to have_received(:increment!).with(:spent_cents, cost_cents)
        expect(monthly_budget).to have_received(:increment!).with(:spent_cents, cost_cents)
      end

      it 'creates usage record' do
        expect {
          described_class.call(
            agent: agent,
            cost_cents: cost_cents,
            usage_metadata: usage_metadata
          )
        }.to change(UsageRecord, :count).by(1)
      end

      it 'broadcasts budget update' do
        described_class.call(
          agent: agent,
          cost_cents: cost_cents,
          usage_metadata: usage_metadata
        )

        expect(ActionCable.server).to have_received(:broadcast).with(
          "budgets_channel",
          {
            type: "budget_update",
            agent_id: agent.id,
            cost_cents: cost_cents,
            timestamp: be_present
          }
        )
      end

      it 'returns budget summaries' do
        result = described_class.call(
          agent: agent,
          cost_cents: cost_cents,
          usage_metadata: usage_metadata
        )

        budgets = result.data[:budgets]
        expect(budgets).to be_an(Array)
        expect(budgets.length).to eq(2)

        daily_summary = budgets.find { |b| b[:period_type] == 'daily' }
        expect(daily_summary).to include(
          period_type: 'daily',
          spent_cents: 450, # 300 + 150
          limit_cents: 1000,
          remaining_cents: 550,
          percentage_used: 45.0,
          exceeded: false
        )
      end
    end

    describe 'budget threshold handling' do
      let!(:budget) { create(:agent_budget, agent: agent, limit_cents: 1000, spent_cents: 800) }

      context 'when budget is exceeded' do
        before do
          allow(budget).to receive(:exceeded?).and_return(true)
          allow(budget).to receive(:warning_threshold?).and_return(false)
        end

        it 'logs warning and sends exceeded alert' do
          expect(Rails.logger).to receive(:warn).with(/exceeded.*budget/)
          
          described_class.call(
            agent: agent,
            cost_cents: cost_cents
          )

          expect(BudgetAlertJob).to have_received(:perform_async).with(agent.id, budget.id, "exceeded")
        end
      end

      context 'when budget hits warning threshold' do
        before do
          allow(budget).to receive(:exceeded?).and_return(false)
          allow(budget).to receive(:warning_threshold?).and_return(true)
          allow(budget).to receive(:alert_sent?).and_return(false)
          allow(budget).to receive(:percentage_used).and_return(85.0)
        end

        it 'logs info and sends warning alert' do
          expect(Rails.logger).to receive(:info).with(/85.0%.*budget/)
          
          described_class.call(
            agent: agent,
            cost_cents: cost_cents
          )

          expect(BudgetAlertJob).to have_received(:perform_async).with(agent.id, budget.id, "warning")
        end
      end

      context 'when warning alert already sent' do
        before do
          allow(budget).to receive(:exceeded?).and_return(false)
          allow(budget).to receive(:warning_threshold?).and_return(true)
          allow(budget).to receive(:alert_sent?).and_return(true)
        end

        it 'does not send duplicate warning alert' do
          described_class.call(
            agent: agent,
            cost_cents: cost_cents
          )

          expect(BudgetAlertJob).not_to have_received(:perform_async)
        end
      end
    end

    describe 'transaction handling' do
      let!(:budget) { create(:agent_budget, agent: agent) }

      context 'when budget update fails' do
        before do
          allow(budget).to receive(:increment!).and_raise(ActiveRecord::RecordInvalid, "Validation failed")
        end

        it 'rolls back transaction and returns failure' do
          expect {
            described_class.call(agent: agent, cost_cents: cost_cents)
          }.not_to change(UsageRecord, :count)

          result = described_class.call(agent: agent, cost_cents: cost_cents)
          expect(result.success?).to be false
          expect(result.error).to eq("Failed to record spend: Validation failed")
        end

        it 'does not broadcast or send alerts when transaction fails' do
          described_class.call(agent: agent, cost_cents: cost_cents)

          expect(ActionCable.server).not_to have_received(:broadcast)
          expect(BudgetAlertJob).not_to have_received(:perform_async)
        end
      end

      context 'when usage record creation fails' do
        before do
          allow(UsageRecord).to receive(:create!).and_raise(ActiveRecord::RecordInvalid, "Missing agent")
        end

        it 'rolls back budget updates' do
          original_spent = budget.spent_cents

          described_class.call(agent: agent, cost_cents: cost_cents)

          budget.reload
          expect(budget.spent_cents).to eq(original_spent) # Should not be updated due to rollback
        end
      end
    end

    describe 'metadata handling' do
      context 'with nil metadata' do
        it 'handles nil metadata gracefully' do
          result = described_class.call(
            agent: agent,
            cost_cents: cost_cents,
            usage_metadata: nil
          )

          expect(result.success?).to be true
          usage_record = result.data[:usage_record]
          expect(usage_record.metadata).to eq({})
        end
      end

      context 'with complex metadata' do
        let(:complex_metadata) do
          {
            model: "gpt-4",
            tokens: { input: 100, output: 50 },
            session: { id: 123, type: "chat" },
            tools_used: ["web_search", "calculator"]
          }
        end

        it 'stores complex metadata correctly' do
          result = described_class.call(
            agent: agent,
            cost_cents: cost_cents,
            usage_metadata: complex_metadata
          )

          usage_record = result.data[:usage_record]
          expect(usage_record.metadata).to eq(complex_metadata.deep_stringify_keys)
        end
      end
    end

    describe 'zero and negative costs' do
      context 'with zero cost' do
        it 'records zero cost spending' do
          result = described_class.call(
            agent: agent,
            cost_cents: 0
          )

          expect(result.success?).to be true
          expect(result.data[:usage_record].cost_cents).to eq(0)
        end
      end

      context 'with negative cost (refund)' do
        let!(:budget) { create(:agent_budget, agent: agent, spent_cents: 500) }

        it 'handles negative costs (decrements spending)' do
          described_class.call(
            agent: agent,
            cost_cents: -100
          )

          expect(budget).to have_received(:increment!).with(:spent_cents, -100)
        end

        it 'records negative cost in usage record' do
          result = described_class.call(
            agent: agent,
            cost_cents: -100
          )

          expect(result.data[:usage_record].cost_cents).to eq(-100)
        end
      end
    end

    describe 'multiple budgets with different states' do
      let!(:exceeded_budget) { create(:agent_budget, agent: agent, period_type: 'daily', spent_cents: 950, limit_cents: 1000) }
      let!(:warning_budget) { create(:agent_budget, agent: agent, period_type: 'weekly', spent_cents: 700, limit_cents: 1000) }
      let!(:normal_budget) { create(:agent_budget, agent: agent, period_type: 'monthly', spent_cents: 100, limit_cents: 1000) }

      before do
        allow(exceeded_budget).to receive(:exceeded?).and_return(true)
        allow(exceeded_budget).to receive(:warning_threshold?).and_return(false)

        allow(warning_budget).to receive(:exceeded?).and_return(false)
        allow(warning_budget).to receive(:warning_threshold?).and_return(true)
        allow(warning_budget).to receive(:alert_sent?).and_return(false)

        allow(normal_budget).to receive(:exceeded?).and_return(false)
        allow(normal_budget).to receive(:warning_threshold?).and_return(false)
      end

      it 'handles each budget according to its state' do
        described_class.call(agent: agent, cost_cents: cost_cents)

        # Should send both exceeded and warning alerts
        expect(BudgetAlertJob).to have_received(:perform_async).with(agent.id, exceeded_budget.id, "exceeded")
        expect(BudgetAlertJob).to have_received(:perform_async).with(agent.id, warning_budget.id, "warning")
        expect(BudgetAlertJob).to have_received(:perform_async).exactly(2).times
      end
    end
  end
end