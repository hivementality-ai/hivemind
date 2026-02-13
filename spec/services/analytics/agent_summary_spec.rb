# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Analytics::AgentSummary do
  describe '.call' do
    let(:agent) { create(:agent) }

    # Create test data for different time periods
    let!(:old_session) { create(:session, agent: agent, created_at: 2.weeks.ago, status: 'completed') }
    let!(:recent_session_1) { create(:session, agent: agent, created_at: 3.days.ago, status: 'completed', transcript: [{role: "user", content: "Hello"}, {role: "assistant", content: "Hi"}]) }
    let!(:recent_session_2) { create(:session, agent: agent, created_at: 1.day.ago, status: 'active', transcript: [{role: "user", content: "Test"}]) }

    let!(:old_usage) { create(:usage_record, agent: agent, created_at: 2.weeks.ago, input_tokens: 10, output_tokens: 5, cost_cents: 100, llm_model: 'gpt-4') }
    let!(:recent_usage_1) { create(:usage_record, agent: agent, created_at: 3.days.ago, input_tokens: 100, output_tokens: 50, cost_cents: 250, llm_model: 'gpt-4') }
    let!(:recent_usage_2) { create(:usage_record, agent: agent, created_at: 1.day.ago, input_tokens: 200, output_tokens: 75, cost_cents: 300, llm_model: 'claude-3') }

    let(:tool) { create(:tool, name: "web_search") }
    let!(:old_execution) { create(:tool_execution, agent: agent, tool: tool, created_at: 2.weeks.ago, success: true) }
    let!(:recent_execution_1) { create(:tool_execution, agent: agent, tool: tool, created_at: 3.days.ago, success: true) }
    let!(:recent_execution_2) { create(:tool_execution, agent: agent, tool: tool, created_at: 1.day.ago, success: false) }

    describe 'successful analytics generation' do
      context 'with default week period' do
        it 'returns summary for the past week' do
          result = described_class.call(agent: agent)

          expect(result).to be_a(ServiceResponse)
          expect(result.success?).to be true
          
          data = result.data
          expect(data[:agent]).to eq(agent)
          expect(data[:period]).to eq("week")
          expect(data[:sessions]).to be_present
          expect(data[:tokens]).to be_present
          expect(data[:costs]).to be_present
          expect(data[:tools]).to be_present
          expect(data[:models]).to be_present
          expect(data[:daily_usage]).to be_present
        end

        it 'calculates session stats correctly' do
          result = described_class.call(agent: agent)
          sessions = result.data[:sessions]

          expect(sessions[:total]).to eq(2) # Only recent sessions
          expect(sessions[:active]).to eq(1)
          expect(sessions[:completed]).to eq(1)
          expect(sessions[:messages]).to eq(3) # 2 + 1 messages from recent sessions
        end

        it 'calculates token stats correctly' do
          result = described_class.call(agent: agent)
          tokens = result.data[:tokens]

          expect(tokens[:input]).to eq(300) # 100 + 200
          expect(tokens[:output]).to eq(125) # 50 + 75
          expect(tokens[:total]).to eq(425) # 300 + 125
        end

        it 'calculates cost stats correctly' do
          result = described_class.call(agent: agent)
          costs = result.data[:costs]

          expect(costs[:total_cents]).to eq(550) # 250 + 300
          expect(costs[:total_dollars]).to eq(5.50)
          expect(costs[:avg_per_request]).to eq(2.75) # 5.50 / 2 requests
        end

        it 'calculates tool stats correctly' do
          result = described_class.call(agent: agent)
          tools = result.data[:tools]

          expect(tools[:total]).to eq(2) # recent executions only
          expect(tools[:success_rate]).to eq(50.0) # 1 success out of 2
          expect(tools[:by_tool]).to eq({ "web_search" => 2 })
        end

        it 'calculates model stats correctly' do
          result = described_class.call(agent: agent)
          models = result.data[:models]

          # Should be sorted by usage count (descending)
          expect(models).to eq({ "gpt-4" => 1, "claude-3" => 1 })
        end

        it 'calculates daily usage correctly' do
          result = described_class.call(agent: agent)
          daily = result.data[:daily_usage]

          expect(daily).to be_a(Hash)
          expect(daily.keys).to all(be_a(Date))
          
          # Should have entries for days with usage
          usage_dates = [3.days.ago.to_date, 1.day.ago.to_date]
          expect(daily.keys).to match_array(usage_dates)

          # Check daily totals
          daily_3_days_ago = daily[3.days.ago.to_date]
          expect(daily_3_days_ago[:requests]).to eq(1)
          expect(daily_3_days_ago[:cost_cents]).to eq(250)
          expect(daily_3_days_ago[:input_tokens]).to eq(100)
          expect(daily_3_days_ago[:output_tokens]).to eq(50)
        end
      end

      context 'with day period' do
        it 'returns summary for the past day' do
          result = described_class.call(agent: agent, period: "day")

          expect(result.data[:period]).to eq("day")
          
          # Only the most recent session/usage should be included
          sessions = result.data[:sessions]
          expect(sessions[:total]).to eq(1)
          
          tokens = result.data[:tokens]
          expect(tokens[:input]).to eq(200) # Only recent_usage_2
        end
      end

      context 'with month period' do
        it 'returns summary for the past month' do
          result = described_class.call(agent: agent, period: "month")

          expect(result.data[:period]).to eq("month")
          
          # All sessions should be included (even the 2-week old one)
          sessions = result.data[:sessions]
          expect(sessions[:total]).to eq(3)
          
          tokens = result.data[:tokens]
          expect(tokens[:input]).to eq(310) # 10 + 100 + 200
        end
      end

      context 'with invalid period' do
        it 'defaults to week period' do
          result = described_class.call(agent: agent, period: "invalid")

          expect(result.data[:period]).to eq("invalid")
          # But uses week range
          sessions = result.data[:sessions]
          expect(sessions[:total]).to eq(2) # Same as week
        end
      end
    end

    describe 'edge cases' do
      context 'when agent has no data' do
        let(:empty_agent) { create(:agent) }

        it 'returns zeros for all metrics' do
          result = described_class.call(agent: empty_agent)

          expect(result.success?).to be true
          
          data = result.data
          expect(data[:sessions][:total]).to eq(0)
          expect(data[:tokens][:total]).to eq(0)
          expect(data[:costs][:total_cents]).to eq(0)
          expect(data[:costs][:avg_per_request]).to eq(0)
          expect(data[:tools][:total]).to eq(0)
          expect(data[:tools][:success_rate]).to eq(0)
          expect(data[:models]).to eq({})
          expect(data[:daily_usage]).to eq({})
        end
      end

      context 'when sessions have no transcript' do
        let!(:session_no_transcript) { create(:session, agent: agent, created_at: 1.day.ago, transcript: nil) }

        it 'handles nil transcript gracefully' do
          result = described_class.call(agent: agent)

          expect(result.success?).to be true
          # Should not raise error and should count as 0 messages
          sessions = result.data[:sessions]
          expect(sessions[:messages]).to be >= 0
        end
      end

      context 'when tool executions have no associated tool' do
        let!(:orphan_execution) { create(:tool_execution, agent: agent, created_at: 1.day.ago, tool: nil, success: true) }

        it 'handles missing tool associations' do
          # This test assumes the database allows null tool_id
          # If not, you might need to adjust the association or skip this test
          result = described_class.call(agent: agent)
          
          expect(result.success?).to be true
          expect(result.data[:tools][:total]).to be >= 0
        end
      end
    end

    describe 'cost calculations' do
      context 'with single usage record' do
        let(:single_agent) { create(:agent) }
        let!(:single_usage) { create(:usage_record, agent: single_agent, cost_cents: 150) }

        it 'calculates single request average correctly' do
          result = described_class.call(agent: single_agent)
          
          costs = result.data[:costs]
          expect(costs[:avg_per_request]).to eq(1.50)
        end
      end

      context 'with fractional cents' do
        let(:fractional_agent) { create(:agent) }
        let!(:fractional_usage) { create(:usage_record, agent: fractional_agent, cost_cents: 1) }

        it 'handles fractional dollar amounts' do
          result = described_class.call(agent: fractional_agent)
          
          costs = result.data[:costs]
          expect(costs[:total_dollars]).to eq(0.01)
          expect(costs[:avg_per_request]).to eq(0.01)
        end
      end
    end

    describe 'error handling' do
      before do
        # Mock a method to raise an error
        allow_any_instance_of(described_class).to receive(:session_stats).and_raise(StandardError, "Database connection lost")
      end

      it 'returns failure with error message' do
        result = described_class.call(agent: agent)

        expect(result.success?).to be false
        expect(result.error).to eq("Failed to compute agent summary: Database connection lost")
      end
    end
  end
end