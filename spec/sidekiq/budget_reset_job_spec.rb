# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BudgetResetJob, type: :job do
  describe '#perform' do
    let(:agent) { create(:agent) }

    context 'with daily budgets due for reset' do
      let!(:stale_budget) do
        create(:agent_budget, :daily, agent: agent, spent_cents: 3000, reset_at: 2.days.ago)
      end

      it 'resets spent_cents to zero' do
        allow(Audit::Record).to receive(:call)

        described_class.new.perform("daily")

        stale_budget.reload
        expect(stale_budget.spent_cents).to eq(0)
      end

      it 'updates reset_at to current time' do
        allow(Audit::Record).to receive(:call)

        freeze_time do
          described_class.new.perform("daily")

          stale_budget.reload
          expect(stale_budget.reset_at).to be_within(1.second).of(Time.current)
        end
      end

      it 'enqueues an Audit::Record with the reset count' do
        expect(Audit::Record).to receive(:call).with(
          actor_type: "system",
          actor_id: "system",
          action: "budgets.reset",
          resource: nil,
          metadata: { period_type: "daily", count: 1 }
        )

        described_class.new.perform("daily")
      end
    end

    context 'with budgets not yet due for reset' do
      let!(:fresh_budget) do
        create(:agent_budget, :daily, agent: agent, spent_cents: 3000, reset_at: Time.current)
      end

      it 'does not reset fresh budgets' do
        allow(Audit::Record).to receive(:call)

        described_class.new.perform("daily")

        fresh_budget.reload
        expect(fresh_budget.spent_cents).to eq(3000)
      end

      it 'reports zero resets in the audit record' do
        expect(Audit::Record).to receive(:call).with(
          hash_including(metadata: { period_type: "daily", count: 0 })
        )

        described_class.new.perform("daily")
      end
    end

    context 'with weekly budgets' do
      let!(:stale_weekly) do
        create(:agent_budget, :weekly, agent: agent, spent_cents: 5000, reset_at: 2.weeks.ago)
      end

      it 'resets weekly budgets due for reset' do
        allow(Audit::Record).to receive(:call)

        described_class.new.perform("weekly")

        stale_weekly.reload
        expect(stale_weekly.spent_cents).to eq(0)
      end
    end

    context 'with monthly budgets' do
      let!(:stale_monthly) do
        create(:agent_budget, :monthly, agent: agent, spent_cents: 50000, reset_at: 2.months.ago)
      end

      it 'resets monthly budgets due for reset' do
        allow(Audit::Record).to receive(:call)

        described_class.new.perform("monthly")

        stale_monthly.reload
        expect(stale_monthly.spent_cents).to eq(0)
      end
    end

    it 'defaults to daily when no period_type is given' do
      expect(Audit::Record).to receive(:call).with(
        hash_including(metadata: hash_including(period_type: "daily"))
      )

      described_class.new.perform
    end
  end
end
