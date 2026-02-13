# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Budgets::Check do
  describe '.call' do
    let(:agent) { create(:agent) }

    describe 'when no budgets configured' do
      it 'allows by default with unlimited flag' do
        result = described_class.call(agent: agent)

        expect(result).to be_a(ServiceResponse)
        expect(result.success?).to be true
        expect(result.data[:allowed]).to be true
        expect(result.data[:unlimited]).to be true
      end
    end

    describe 'with active budgets' do
      let!(:daily_budget) { create(:agent_budget, agent: agent, period_type: 'daily', limit_cents: 1000) }
      let!(:monthly_budget) { create(:agent_budget, agent: agent, period_type: 'monthly', limit_cents: 5000) }

      before do
        # Mock budget methods
        allow(daily_budget).to receive(:remaining_cents).and_return(600)
        allow(daily_budget).to receive(:spent_cents).and_return(400)
        allow(daily_budget).to receive(:percentage_used).and_return(40.0)
        allow(daily_budget).to receive(:warning_threshold?).and_return(false)

        allow(monthly_budget).to receive(:remaining_cents).and_return(3500)
        allow(monthly_budget).to receive(:spent_cents).and_return(1500)
        allow(monthly_budget).to receive(:percentage_used).and_return(30.0)
        allow(monthly_budget).to receive(:warning_threshold?).and_return(false)
      end

      context 'when within all budget limits' do
        it 'allows the request' do
          result = described_class.call(agent: agent, estimated_cost_cents: 100)

          expect(result.success?).to be true
          expect(result.data[:allowed]).to be true
          expect(result.data[:unlimited]).to be_nil
        end

        it 'returns budget information for each period' do
          result = described_class.call(agent: agent, estimated_cost_cents: 100)

          budgets = result.data[:budgets]
          expect(budgets).to be_an(Array)
          expect(budgets.length).to eq(2)

          daily = budgets.find { |b| b[:period_type] == 'daily' }
          expect(daily).to include(
            period_type: 'daily',
            limit_cents: 1000,
            spent_cents: 400,
            remaining_cents: 600,
            percentage_used: 40.0,
            exceeded: false,
            warning: false
          )

          monthly = budgets.find { |b| b[:period_type] == 'monthly' }
          expect(monthly).to include(
            period_type: 'monthly',
            limit_cents: 5000,
            spent_cents: 1500,
            remaining_cents: 3500,
            percentage_used: 30.0,
            exceeded: false,
            warning: false
          )
        end
      end

      context 'when estimated cost would exceed budget' do
        it 'denies when daily budget would be exceeded' do
          result = described_class.call(agent: agent, estimated_cost_cents: 700) # 400 + 700 > 1000

          expect(result.success?).to be false
          expect(result.error).to eq("Budget exceeded for one or more periods")

          # Should still include budget details in the failed response
          budgets = result.data[:budgets] if result.data
          daily = budgets&.find { |b| b[:period_type] == 'daily' }
          expect(daily[:exceeded]).to be true if daily
        end

        it 'denies when monthly budget would be exceeded' do
          result = described_class.call(agent: agent, estimated_cost_cents: 4000) # 1500 + 4000 > 5000

          expect(result.success?).to be false
          expect(result.error).to eq("Budget exceeded for one or more periods")
        end

        it 'denies when any budget would be exceeded' do
          # Set up scenario where daily is OK but monthly would exceed
          allow(daily_budget).to receive(:spent_cents).and_return(100) # Low daily spend
          allow(monthly_budget).to receive(:spent_cents).and_return(4800) # High monthly spend

          result = described_class.call(agent: agent, estimated_cost_cents: 300) # Would exceed monthly

          expect(result.success?).to be false
        end
      end

      context 'when approaching budget limits (warnings)' do
        before do
          allow(daily_budget).to receive(:warning_threshold?).and_return(true)
          allow(monthly_budget).to receive(:warning_threshold?).and_return(false)
        end

        it 'allows request but includes warnings' do
          result = described_class.call(agent: agent, estimated_cost_cents: 50)

          expect(result.success?).to be true
          expect(result.data[:allowed]).to be true
          
          warnings = result.data[:warnings]
          expect(warnings).to be_an(Array)
          expect(warnings.length).to eq(1)
          expect(warnings.first[:period_type]).to eq('daily')
          expect(warnings.first[:warning]).to be true
        end
      end

      context 'with zero estimated cost' do
        it 'checks current spending without additional cost' do
          result = described_class.call(agent: agent, estimated_cost_cents: 0)

          expect(result.success?).to be true
          expect(result.data[:allowed]).to be true
        end
      end
    end

    describe 'with multiple budget periods' do
      let!(:daily_budget) { create(:agent_budget, agent: agent, period_type: 'daily', limit_cents: 500) }
      let!(:weekly_budget) { create(:agent_budget, agent: agent, period_type: 'weekly', limit_cents: 2000) }
      let!(:monthly_budget) { create(:agent_budget, agent: agent, period_type: 'monthly', limit_cents: 8000) }

      before do
        allow(daily_budget).to receive(:spent_cents).and_return(450)
        allow(daily_budget).to receive(:remaining_cents).and_return(50)
        allow(daily_budget).to receive(:percentage_used).and_return(90.0)
        allow(daily_budget).to receive(:warning_threshold?).and_return(true)

        allow(weekly_budget).to receive(:spent_cents).and_return(1200)
        allow(weekly_budget).to receive(:remaining_cents).and_return(800)
        allow(weekly_budget).to receive(:percentage_used).and_return(60.0)
        allow(weekly_budget).to receive(:warning_threshold?).and_return(false)

        allow(monthly_budget).to receive(:spent_cents).and_return(3000)
        allow(monthly_budget).to receive(:remaining_cents).and_return(5000)
        allow(monthly_budget).to receive(:percentage_used).and_return(37.5)
        allow(monthly_budget).to receive(:warning_threshold?).and_return(false)
      end

      it 'checks all budgets and returns comprehensive results' do
        result = described_class.call(agent: agent, estimated_cost_cents: 30)

        expect(result.success?).to be true
        
        budgets = result.data[:budgets]
        expect(budgets.length).to eq(3)
        
        # All periods should show not exceeded
        budgets.each do |budget_info|
          expect(budget_info[:exceeded]).to be false
        end

        # Only daily should show warning
        warnings = result.data[:warnings]
        expect(warnings.length).to eq(1)
        expect(warnings.first[:period_type]).to eq('daily')
      end

      it 'denies if any single budget would be exceeded' do
        # Request would exceed daily limit but not others
        result = described_class.call(agent: agent, estimated_cost_cents: 100) # 450 + 100 > 500

        expect(result.success?).to be false
        
        # Daily should be marked as exceeded, others not
        budgets = result.data[:budgets] if result.data
        if budgets
          daily = budgets.find { |b| b[:period_type] == 'daily' }
          weekly = budgets.find { |b| b[:period_type] == 'weekly' }
          monthly = budgets.find { |b| b[:period_type] == 'monthly' }
          
          expect(daily[:exceeded]).to be true
          expect(weekly[:exceeded]).to be false
          expect(monthly[:exceeded]).to be false
        end
      end
    end

    describe 'edge cases' do
      context 'when budget has been exactly spent' do
        let!(:exact_budget) { create(:agent_budget, agent: agent, limit_cents: 1000) }

        before do
          allow(exact_budget).to receive(:spent_cents).and_return(1000)
          allow(exact_budget).to receive(:remaining_cents).and_return(0)
          allow(exact_budget).to receive(:percentage_used).and_return(100.0)
          allow(exact_budget).to receive(:warning_threshold?).and_return(false)
        end

        it 'denies any additional spending' do
          result = described_class.call(agent: agent, estimated_cost_cents: 1)

          expect(result.success?).to be false
          expect(result.error).to eq("Budget exceeded for one or more periods")
        end

        it 'allows zero cost operations' do
          result = described_class.call(agent: agent, estimated_cost_cents: 0)

          expect(result.success?).to be true
          expect(result.data[:allowed]).to be true
        end
      end

      context 'when budget methods raise exceptions' do
        let!(:faulty_budget) { create(:agent_budget, agent: agent) }

        before do
          allow(faulty_budget).to receive(:remaining_cents).and_raise(StandardError, "Database error")
        end

        it 'returns failure with error message' do
          result = described_class.call(agent: agent, estimated_cost_cents: 100)

          expect(result.success?).to be false
          expect(result.error).to eq("Budget check failed: Database error")
        end
      end
    end

    describe 'negative estimated costs' do
      let!(:budget) { create(:agent_budget, agent: agent, limit_cents: 1000) }

      before do
        allow(budget).to receive(:spent_cents).and_return(900)
        allow(budget).to receive(:remaining_cents).and_return(100)
        allow(budget).to receive(:percentage_used).and_return(90.0)
        allow(budget).to receive(:warning_threshold?).and_return(true)
      end

      it 'handles negative estimated costs (refunds)' do
        # Negative cost (like a refund) should make budget check more permissive
        result = described_class.call(agent: agent, estimated_cost_cents: -50)

        expect(result.success?).to be true
        expect(result.data[:allowed]).to be true

        budget_info = result.data[:budgets].first
        expect(budget_info[:exceeded]).to be false # 900 + (-50) = 850 < 1000
      end
    end
  end
end