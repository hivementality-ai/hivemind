# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentBudget, type: :model do
  describe 'associations' do
    it { should belong_to(:agent) }
  end

  describe 'validations' do
    it { should validate_presence_of(:period) }
    it { should validate_numericality_of(:limit_cents).is_greater_than_or_equal_to(0).allow_nil }
    it { should validate_numericality_of(:spent_cents).is_greater_than_or_equal_to(0).allow_nil }
  end

  describe '#remaining_cents' do
    context 'when limit_cents is set' do
      it 'returns remaining budget' do
        budget = build(:agent_budget, limit_cents: 10000, spent_cents: 3000)
        expect(budget.remaining_cents).to eq(7000)
      end

      it 'handles negative remaining (overspend)' do
        budget = build(:agent_budget, limit_cents: 10000, spent_cents: 12000)
        expect(budget.remaining_cents).to eq(-2000)
      end

      it 'handles nil spent_cents' do
        budget = build(:agent_budget, limit_cents: 10000, spent_cents: nil)
        expect(budget.remaining_cents).to eq(10000)
      end
    end

    context 'when limit_cents is nil' do
      it 'returns 0' do
        budget = build(:agent_budget, limit_cents: nil, spent_cents: 3000)
        expect(budget.remaining_cents).to eq(0)
      end
    end
  end

  describe '#percentage_used' do
    context 'when limit_cents is set' do
      it 'returns percentage of budget used' do
        budget = build(:agent_budget, limit_cents: 10000, spent_cents: 5000)
        expect(budget.percentage_used).to eq(50.0)
      end

      it 'returns over 100% for overspend' do
        budget = build(:agent_budget, limit_cents: 10000, spent_cents: 15000)
        expect(budget.percentage_used).to eq(150.0)
      end

      it 'handles nil spent_cents' do
        budget = build(:agent_budget, limit_cents: 10000, spent_cents: nil)
        expect(budget.percentage_used).to eq(0.0)
      end
    end

    context 'when limit_cents is nil' do
      it 'returns 0' do
        budget = build(:agent_budget, limit_cents: nil, spent_cents: 5000)
        expect(budget.percentage_used).to eq(0)
      end
    end

    context 'when limit_cents is zero' do
      it 'returns 0' do
        budget = build(:agent_budget, limit_cents: 0, spent_cents: 0)
        expect(budget.percentage_used).to eq(0)
      end
    end
  end

  describe '#exceeded?' do
    context 'when limit_cents is set' do
      it 'returns true when spent exceeds limit' do
        budget = build(:agent_budget, limit_cents: 10000, spent_cents: 11000)
        expect(budget.exceeded?).to be true
      end

      it 'returns true when spent equals limit' do
        budget = build(:agent_budget, limit_cents: 10000, spent_cents: 10000)
        expect(budget.exceeded?).to be true
      end

      it 'returns false when spent is below limit' do
        budget = build(:agent_budget, limit_cents: 10000, spent_cents: 5000)
        expect(budget.exceeded?).to be false
      end
    end

    context 'when limit_cents is nil' do
      it 'returns false' do
        budget = build(:agent_budget, limit_cents: nil, spent_cents: 5000)
        expect(budget.exceeded?).to be false
      end
    end
  end

  describe '#warning_threshold?' do
    it 'returns true when usage is 80% or more' do
      budget = build(:agent_budget, limit_cents: 10000, spent_cents: 8000)
      expect(budget.warning_threshold?).to be true
    end

    it 'returns true when usage is over 80%' do
      budget = build(:agent_budget, limit_cents: 10000, spent_cents: 9500)
      expect(budget.warning_threshold?).to be true
    end

    it 'returns false when usage is below 80%' do
      budget = build(:agent_budget, limit_cents: 10000, spent_cents: 7000)
      expect(budget.warning_threshold?).to be false
    end
  end

  describe '#reset!' do
    let(:budget) { create(:agent_budget, spent_cents: 5000) }

    it 'resets spent_cents to 0' do
      budget.reset!
      expect(budget.spent_cents).to eq(0)
    end

    it 'sets reset_at to current time' do
      budget.reset!
      expect(budget.reset_at).to be_within(1.second).of(Time.current)
    end

    it 'persists the reset' do
      budget.reset!
      budget.reload
      expect(budget.spent_cents).to eq(0)
      expect(budget.reset_at).to be_present
    end
  end

  describe 'factory' do
    it 'creates a valid agent budget' do
      expect(build(:agent_budget)).to be_valid
    end

    it 'creates valid budgets with traits' do
      expect(build(:agent_budget, :daily)).to be_valid
      expect(build(:agent_budget, :weekly)).to be_valid
      expect(build(:agent_budget, :monthly)).to be_valid
      expect(build(:agent_budget, :exceeded)).to be_valid
      expect(build(:agent_budget, :warning)).to be_valid
      expect(build(:agent_budget, :low_usage)).to be_valid
    end
  end
end
