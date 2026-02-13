# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::SessionStatusExecutor, type: :service do
  let(:agent) { create(:agent, name: 'Test Agent') }
  let(:executor) { described_class.new(input: input, config: {}, agent: agent) }

  describe '#call' do
    context 'with specific session key' do
      let(:session) { create(:session, session_key: 'test-session-123', title: 'Test Session', agent: agent, status: 'active') }
      let(:input) { { "session_key" => "test-session-123" } }

      before do
        session.update(transcript: [
          { role: 'user', content: 'Hello' },
          { role: 'assistant', content: 'Hi there!' }
        ])

        create(:usage_record, session: session, input_tokens: 100, output_tokens: 50, cost_cents: 15, llm_model: 'gpt-4')
        create(:usage_record, session: session, input_tokens: 80, output_tokens: 30, cost_cents: 10, llm_model: 'gpt-3.5-turbo')
      end

      it 'returns session status information' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Session: Test Session")
        expect(result.data[:output]).to include("Agent: Test Agent")
        expect(result.data[:output]).to include("Status: active")
        expect(result.data[:output]).to include("Messages: 2")
        expect(result.data[:output]).to include("API Requests: 2")
        expect(result.data[:output]).to include("Total Tokens: 260")
        expect(result.data[:output]).to include("Total Cost: $0.2500")
        expect(result.data[:output]).to include("Models: gpt-4, gpt-3.5-turbo")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'includes timestamps' do
        result = executor.call
        expect(result.data[:output]).to include("Created:")
        expect(result.data[:output]).to include("Last Active:")
      end

      context 'with no usage records' do
        before do
          UsageRecord.where(session: session).destroy_all
        end

        it 'shows zero usage' do
          result = executor.call
          expect(result.data[:output]).to include("API Requests: 0")
          expect(result.data[:output]).to include("Total Tokens: 0")
          expect(result.data[:output]).to include("Total Cost: $0.0000")
          expect(result.data[:output]).not_to include("Models:")
        end
      end

      context 'with nil transcript' do
        before do
          session.update(transcript: nil)
        end

        it 'shows 0 messages' do
          result = executor.call
          expect(result.data[:output]).to include("Messages: 0")
        end
      end

      context 'with session having no title' do
        before do
          session.update(title: nil)
        end

        it 'shows session key instead' do
          result = executor.call
          expect(result.data[:output]).to include("Session: test-session-123")
        end
      end

      context 'with session having no agent' do
        before do
          session.update(agent: nil)
        end

        it 'shows dash for agent' do
          result = executor.call
          expect(result.data[:output]).to include("Agent: —")
        end
      end
    end

    context 'without session key' do
      let(:input) { {} }

      context 'when agent has sessions' do
        let!(:old_session) { create(:session, agent: agent, updated_at: 2.hours.ago) }
        let!(:recent_session) { create(:session, agent: agent, title: 'Recent Session', updated_at: 1.hour.ago) }

        it 'returns most recent session for agent' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("Session: Recent Session")
        end
      end

      context 'when agent has no sessions' do
        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No session found")
        end
      end
    end

    context 'with empty session key' do
      let(:input) { { "session_key" => "  " } }
      let!(:recent_session) { create(:session, agent: agent, title: 'Default Session') }

      it 'falls back to agent\'s recent session' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Session: Default Session")
      end
    end

    context 'with non-existent session key' do
      let(:input) { { "session_key" => "non-existent-key" } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No session found")
      end
    end

    context 'without agent' do
      let(:executor) { described_class.new(input: input, config: {}, agent: nil) }
      let(:input) { {} }

      it 'returns failure when no session key provided' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No session found")
      end

      context 'with valid session key' do
        let(:session) { create(:session, session_key: 'system-session', title: 'System Session') }
        let(:input) { { "session_key" => "system-session" } }

        it 'can still find session by key' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("Session: System Session")
        end
      end
    end

    context 'with complex usage data' do
      let(:session) { create(:session, session_key: 'complex-session', agent: agent) }
      let(:input) { { "session_key" => "complex-session" } }

      before do
        # Create usage records with fractional costs
        create(:usage_record, session: session, input_tokens: 1000, output_tokens: 500, cost_cents: 123, llm_model: 'claude-3-sonnet')
        create(:usage_record, session: session, input_tokens: 2000, output_tokens: 1000, cost_cents: 456, llm_model: 'claude-3-haiku')
        create(:usage_record, session: session, input_tokens: 0, output_tokens: 0, cost_cents: 1, llm_model: 'claude-3-sonnet')  # Duplicate model
      end

      it 'calculates totals correctly' do
        result = executor.call
        expect(result.data[:output]).to include("Total Tokens: 4500")
        expect(result.data[:output]).to include("Total Cost: $5.8000")
        expect(result.data[:output]).to include("API Requests: 3")
      end

      it 'deduplicates models in the list' do
        result = executor.call
        models_line = result.data[:output].lines.find { |line| line.include?('Models:') }
        expect(models_line).to include("claude-3-sonnet")
        expect(models_line).to include("claude-3-haiku")
        expect(models_line.scan(/claude-3-sonnet/).size).to eq(1)  # Should appear only once
      end
    end

    context 'when database query fails' do
      let(:session) { create(:session, session_key: 'failing-session', agent: agent) }
      let(:input) { { "session_key" => "failing-session" } }

      before do
        allow(UsageRecord).to receive(:where).and_raise(StandardError.new("Database error"))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Session status failed: Database error")
      end
    end

    context 'with zero cost records' do
      let(:session) { create(:session, session_key: 'free-session', agent: agent) }
      let(:input) { { "session_key" => "free-session" } }

      before do
        create(:usage_record, session: session, input_tokens: 100, output_tokens: 50, cost_cents: 0, llm_model: 'free-model')
      end

      it 'shows zero cost correctly' do
        result = executor.call
        expect(result.data[:output]).to include("Total Cost: $0.0000")
      end
    end

    context 'with very high costs' do
      let(:session) { create(:session, session_key: 'expensive-session', agent: agent) }
      let(:input) { { "session_key" => "expensive-session" } }

      before do
        create(:usage_record, session: session, cost_cents: 999999)  # $9999.99
      end

      it 'formats large costs correctly' do
        result = executor.call
        expect(result.data[:output]).to include("Total Cost: $9999.9900")
      end
    end

    context 'with timestamp formatting' do
      let(:session) { create(:session, session_key: 'time-session', agent: agent) }
      let(:input) { { "session_key" => "time-session" } }

      before do
        # Set specific times for consistent testing
        session.update(
          created_at: Time.zone.parse('2023-12-25 15:30:45'),
          updated_at: Time.zone.parse('2023-12-25 16:45:30')
        )
      end

      it 'formats timestamps correctly' do
        result = executor.call
        expect(result.data[:output]).to include("Created: 2023-12-25 15:30")
        expect(result.data[:output]).to include("Last Active: 2023-12-25 16:45")
      end
    end
  end
end