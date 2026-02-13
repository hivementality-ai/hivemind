# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Analytics::TeamSummary do
  describe '.call' do
    let(:team) { create(:team) }
    let(:agent1) { create(:agent, team: team, enabled: true) }
    let(:agent2) { create(:agent, team: team, enabled: false) }
    let(:other_team_agent) { create(:agent, enabled: true) } # Different team

    # Create test data
    let!(:session1) { create(:session, agent: agent1, created_at: 2.days.ago) }
    let!(:session2) { create(:session, agent: agent2, created_at: 1.day.ago) }
    let!(:old_session) { create(:session, agent: agent1, created_at: 2.weeks.ago) }
    let!(:other_session) { create(:session, agent: other_team_agent, created_at: 1.day.ago) }

    let!(:usage1) { create(:usage_record, agent: agent1, created_at: 2.days.ago, input_tokens: 100, output_tokens: 50, cost_cents: 200, llm_model: 'gpt-4') }
    let!(:usage2) { create(:usage_record, agent: agent2, created_at: 1.day.ago, input_tokens: 200, output_tokens: 75, cost_cents: 300, llm_model: 'claude-3') }
    let!(:usage3) { create(:usage_record, agent: agent1, created_at: 1.day.ago, input_tokens: 150, output_tokens: 60, cost_cents: 250, llm_model: 'gpt-4') }
    let!(:old_usage) { create(:usage_record, agent: agent1, created_at: 2.weeks.ago, cost_cents: 100) }
    let!(:other_usage) { create(:usage_record, agent: other_team_agent, created_at: 1.day.ago, cost_cents: 150) }

    describe 'team-specific summary' do
      context 'with default week period' do
        it 'returns summary for the specified team' do
          result = described_class.call(team: team)

          expect(result).to be_a(ServiceResponse)
          expect(result.success?).to be true
          
          data = result.data
          expect(data[:team]).to eq(team)
          expect(data[:period]).to eq("week")
          expect(data[:agents]).to match_array([agent1, agent2])
          expect(data[:summary]).to be_present
          expect(data[:per_agent]).to be_present
        end

        it 'calculates team summary correctly' do
          result = described_class.call(team: team)
          summary = result.data[:summary]

          expect(summary[:total_sessions]).to eq(2) # session1 and session2 (not old_session)
          expect(summary[:active_agents]).to eq(1) # only agent1 is enabled
          expect(summary[:total_cost_cents]).to eq(750) # 200 + 300 + 250
          expect(summary[:total_cost_dollars]).to eq(7.50)
          expect(summary[:total_input_tokens]).to eq(450) # 100 + 200 + 150
          expect(summary[:total_output_tokens]).to eq(185) # 50 + 75 + 60
          expect(summary[:total_tokens]).to eq(635) # 450 + 185
          expect(summary[:total_requests]).to eq(3) # 3 usage records
          expect(summary[:avg_cost_per_request]).to eq(2.50) # 7.50 / 3
        end

        it 'calculates per-agent stats correctly' do
          result = described_class.call(team: team)
          per_agent = result.data[:per_agent]

          expect(per_agent).to be_an(Array)
          expect(per_agent.length).to eq(2)

          # Should be sorted by cost descending
          top_agent = per_agent.first
          expect(top_agent[:agent]).to eq(agent1)
          expect(top_agent[:sessions]).to eq(1) # session1
          expect(top_agent[:requests]).to eq(2) # usage1 and usage3
          expect(top_agent[:cost_cents]).to eq(450) # 200 + 250
          expect(top_agent[:input_tokens]).to eq(250) # 100 + 150
          expect(top_agent[:output_tokens]).to eq(110) # 50 + 60
          expect(top_agent[:models_used]).to eq(['gpt-4'])

          second_agent = per_agent.second
          expect(second_agent[:agent]).to eq(agent2)
          expect(second_agent[:sessions]).to eq(1) # session2
          expect(second_agent[:requests]).to eq(1) # usage2
          expect(second_agent[:cost_cents]).to eq(300)
          expect(second_agent[:models_used]).to eq(['claude-3'])
        end
      end

      context 'with day period' do
        it 'returns summary for the past day only' do
          result = described_class.call(team: team, period: "day")

          summary = result.data[:summary]
          expect(summary[:total_sessions]).to eq(1) # Only session2
          expect(summary[:total_requests]).to eq(2) # usage2 and usage3

          per_agent = result.data[:per_agent]
          agent1_stats = per_agent.find { |s| s[:agent] == agent1 }
          expect(agent1_stats[:requests]).to eq(1) # Only usage3
        end
      end

      context 'with month period' do
        it 'includes older data within the month' do
          result = described_class.call(team: team, period: "month")

          summary = result.data[:summary]
          expect(summary[:total_sessions]).to eq(3) # All sessions including old_session
          expect(summary[:total_requests]).to eq(4) # All usage records including old_usage
        end
      end
    end

    describe 'global summary (no team specified)' do
      it 'returns summary for all agents' do
        result = described_class.call(team: nil)

        data = result.data
        expect(data[:team]).to be_nil
        expect(data[:agents]).to include(agent1, agent2, other_team_agent)

        summary = data[:summary]
        # Should include other_team_agent's data too
        expect(summary[:total_sessions]).to eq(3) # session1, session2, other_session
        expect(summary[:total_cost_cents]).to eq(900) # 750 + 150
        expect(summary[:active_agents]).to eq(2) # agent1 and other_team_agent
      end

      it 'includes all agents in per-agent breakdown' do
        result = described_class.call(team: nil)
        per_agent = result.data[:per_agent]

        agents = per_agent.map { |s| s[:agent] }
        expect(agents).to include(agent1, agent2, other_team_agent)
      end
    end

    describe 'edge cases' do
      context 'with team that has no agents' do
        let(:empty_team) { create(:team) }

        it 'returns zeros for all metrics' do
          result = described_class.call(team: empty_team)

          expect(result.success?).to be true
          
          summary = result.data[:summary]
          expect(summary[:total_sessions]).to eq(0)
          expect(summary[:active_agents]).to eq(0)
          expect(summary[:total_cost_cents]).to eq(0)
          expect(summary[:avg_cost_per_request]).to eq(0)

          expect(result.data[:per_agent]).to eq([])
        end
      end

      context 'with agents that have no usage' do
        let(:unused_agent) { create(:agent, team: team) }

        it 'includes agent with zero stats' do
          result = described_class.call(team: team)
          per_agent = result.data[:per_agent]

          unused_stats = per_agent.find { |s| s[:agent] == unused_agent }
          expect(unused_stats).to be_present
          expect(unused_stats[:sessions]).to eq(0)
          expect(unused_stats[:requests]).to eq(0)
          expect(unused_stats[:cost_cents]).to eq(0)
          expect(unused_stats[:models_used]).to eq([])
        end
      end

      context 'with invalid period' do
        it 'defaults to week period' do
          result = described_class.call(team: team, period: "invalid")

          expect(result.data[:period]).to eq("invalid")
          # But behavior should match week
          summary = result.data[:summary]
          expect(summary[:total_sessions]).to eq(2) # Same as week
        end
      end
    end

    describe 'sorting' do
      it 'sorts agents by cost in descending order' do
        result = described_class.call(team: team)
        per_agent = result.data[:per_agent]

        costs = per_agent.map { |s| s[:cost_cents] }
        expect(costs).to eq(costs.sort.reverse)
      end

      context 'with equal costs' do
        let!(:equal_cost_usage) { create(:usage_record, agent: agent2, created_at: 1.day.ago, cost_cents: 150) }

        it 'maintains stable sort order' do
          # Update agent1 to have same total cost as agent2
          usage3.update(cost_cents: 150) # agent1 total becomes 350, same as agent2 (300+150)

          result = described_class.call(team: team)
          per_agent = result.data[:per_agent]

          # Should not raise errors and should handle ties gracefully
          expect(per_agent.length).to eq(2)
          costs = per_agent.map { |s| s[:cost_cents] }
          expect(costs.first).to be >= costs.last
        end
      end
    end

    describe 'models used calculation' do
      it 'removes duplicates and nil values' do
        # Add another usage with same model for agent1
        create(:usage_record, agent: agent1, created_at: 1.day.ago, llm_model: 'gpt-4')
        # Add usage with nil model
        create(:usage_record, agent: agent1, created_at: 1.day.ago, llm_model: nil)

        result = described_class.call(team: team)
        per_agent = result.data[:per_agent]

        agent1_stats = per_agent.find { |s| s[:agent] == agent1 }
        expect(agent1_stats[:models_used]).to eq(['gpt-4']) # Only unique, non-nil models
      end
    end

    describe 'error handling' do
      before do
        allow(Session).to receive(:where).and_raise(StandardError, "Database connection failed")
      end

      it 'returns failure with error message' do
        result = described_class.call(team: team)

        expect(result.success?).to be false
        expect(result.error).to eq("Failed to compute team summary: Database connection failed")
      end
    end
  end
end