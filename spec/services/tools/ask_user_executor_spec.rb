# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::AskUserExecutor, type: :service do
  let(:session) { create(:session) }
  let(:agent) { create(:agent) }
  let(:input) { { 'question' => 'What color should the button be?' } }
  let(:config) { { session: session } }
  let(:executor) { described_class.new(input: input, config: config, agent: agent) }

  before do
    allow(ActionCable.server).to receive(:broadcast)
    allow(Rails.cache).to receive(:write)
    allow(Rails.cache).to receive(:read)
    allow(Rails.cache).to receive(:delete)
  end

  describe '#call' do
    context 'with valid question' do
      let(:redis_key) { "ask_user_pending:#{session.id}" }

      context 'when user responds in time' do
        before do
          # Mock the question storage
          expect(Rails.cache).to receive(:write).with(redis_key, anything, expires_in: anything)

          # Mock the ActionCable broadcast
          expect(ActionCable.server).to receive(:broadcast).with(
            "session_#{session.id}",
            {
              type: "agent_question",
              question: "What color should the button be?",
              timestamp: anything
            }
          )

          # Mock the polling loop - first call returns pending, second returns answer
          call_count = 0
          allow(Rails.cache).to receive(:read).with(redis_key) do
            call_count += 1
            case call_count
            when 1
              { question: "What color should the button be?", asked_at: Time.current.iso8601 }.to_json
            when 2
              { question: "What color should the button be?", answer: "Blue", answered_at: Time.current.iso8601 }.to_json
            else
              nil
            end
          end

          # Mock cleanup
          expect(Rails.cache).to receive(:delete).with(redis_key)

          # Mock sleep to speed up test
          allow(executor).to receive(:sleep)
        end

        it 'returns user response' do
          result = executor.call

          expect(result).to be_success
          expect(result.data[:output]).to eq("User responded: Blue")
          expect(result.data[:user_response]).to eq("Blue")
          expect(result.data[:exit_code]).to eq(0)
        end
      end

      context 'when question is answered (cache deleted)' do
        before do
          # Mock the question storage
          expect(Rails.cache).to receive(:write).with(redis_key, anything, expires_in: anything)

          # Mock the ActionCable broadcast
          expect(ActionCable.server).to receive(:broadcast)

          # Mock the polling loop - cache returns nil (question was deleted/answered)
          allow(Rails.cache).to receive(:read).with(redis_key).and_return(nil)

          # Mock sleep to speed up test
          allow(executor).to receive(:sleep)
        end

        it 'returns no response error' do
          result = executor.call

          expect(result).not_to be_success
          expect(result.error).to eq("No response received from user")
        end
      end
    end

    context 'with blank question' do
      let(:input) { { 'question' => '' } }

      it 'returns validation error' do
        result = executor.call

        expect(result).not_to be_success
        expect(result.error).to eq("Question cannot be blank")
      end
    end

    context 'without session' do
      let(:config) { {} }

      it 'returns session error' do
        result = executor.call

        expect(result).not_to be_success
        expect(result.error).to eq("Session required for ask_user tool")
      end
    end

    context 'when error occurs' do
      before do
        allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError.new("Connection failed"))
        allow(Rails.cache).to receive(:delete)
      end

      it 'cleans up and returns error' do
        result = executor.call

        expect(result).not_to be_success
        expect(result.error).to include("Ask user failed: Connection failed")
        expect(Rails.cache).to have_received(:delete).with("ask_user_pending:#{session.id}")
      end
    end
  end
end
