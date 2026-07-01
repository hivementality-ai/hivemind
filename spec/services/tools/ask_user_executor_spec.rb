# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::AskUserExecutor, type: :service do
  let(:session) { create(:session) }
  let(:agent) { create(:agent) }
  let(:config) { { session: session } }

  before do
    allow(ActionCable.server).to receive(:broadcast)
    allow(Rails.cache).to receive(:write)
    allow(Rails.cache).to receive(:read)
    allow(Rails.cache).to receive(:delete)
  end

  # ─── helpers ────────────────────────────────────────────

  def make_executor(input)
    described_class.new(input: input, config: config, agent: agent)
  end

  def stub_poll_then_answer(executor, redis_key, pending_base)
    call_count = 0
    allow(Rails.cache).to receive(:read).with(redis_key) do
      call_count += 1
      case call_count
      when 1 then pending_base.to_json
      when 2 then pending_base.merge("answer" => "Blue").to_json
      else nil
      end
    end
    allow(Rails.cache).to receive(:delete).with(redis_key)
    allow(executor).to receive(:sleep)
  end

  # ─── new questions-array format ─────────────────────────

  describe '#call with questions array' do
    let(:questions_input) do
      {
        'questions' => [
          {
            'question' => 'What color should the button be?',
            'header'   => 'Color',
            'options'  => [
              { 'label' => 'Blue',  'description' => 'Primary brand color' },
              { 'label' => 'Green', 'description' => nil }
            ],
            'multiSelect' => false
          }
        ]
      }
    end
    let(:executor) { make_executor(questions_input) }
    let(:redis_key) { "ask_user_pending:#{session.id}" }

    context 'when user responds in time' do
      before do
        stub_poll_then_answer(executor, redis_key,
          { "questions" => anything, "asked_at" => Time.current.iso8601 })

        allow(Rails.cache).to receive(:write).with(redis_key, anything, expires_in: anything)
      end

      it 'broadcasts questions array with options' do
        executor.call

        expect(ActionCable.server).to have_received(:broadcast).with(
          "session_#{session.id}",
          hash_including(
            type: "agent_question",
            questions: array_including(
              hash_including("question" => "What color should the button be?", "multiSelect" => false)
            )
          )
        )
      end

      it 'returns success with user response' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("User responded: Blue")
        expect(result.data[:user_response]).to eq("Blue")
      end
    end

    context 'when question text is blank inside array' do
      let(:executor) { make_executor('questions' => [ { 'question' => '  ', 'options' => [] } ]) }

      it 'returns validation error' do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("questions cannot be blank")
      end
    end
  end

  # ─── legacy single question string ──────────────────────

  describe '#call with legacy question string' do
    let(:executor) { make_executor('question' => 'What color should the button be?') }
    let(:redis_key) { "ask_user_pending:#{session.id}" }

    context 'when user responds in time' do
      before do
        stub_poll_then_answer(executor, redis_key,
          { "questions" => anything, "asked_at" => Time.current.iso8601 })

        allow(Rails.cache).to receive(:write).with(redis_key, anything, expires_in: anything)
      end

      it 'normalises to questions array and broadcasts' do
        executor.call

        expect(ActionCable.server).to have_received(:broadcast).with(
          "session_#{session.id}",
          hash_including(
            type: "agent_question",
            questions: array_including(
              hash_including("question" => "What color should the button be?", "options" => [])
            )
          )
        )
      end

      it 'returns success' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:user_response]).to eq("Blue")
      end
    end

    context 'when question is answered (cache key deleted)' do
      before do
        allow(Rails.cache).to receive(:write)
        allow(Rails.cache).to receive(:read).with(redis_key).and_return(nil)
        allow(executor).to receive(:sleep)
      end

      it 'returns failure' do
        result = executor.call
        expect(result).not_to be_success
        expect(result.error).to eq("No response received from user")
      end
    end
  end

  # ─── blank input ────────────────────────────────────────

  describe '#call with blank input' do
    it 'returns error for empty questions array' do
      result = make_executor('questions' => []).call
      expect(result).not_to be_success
      expect(result.error).to eq("questions cannot be blank")
    end

    it 'returns error when both question and questions are absent' do
      result = make_executor({}).call
      expect(result).not_to be_success
      expect(result.error).to eq("questions cannot be blank")
    end
  end

  # ─── missing session ────────────────────────────────────

  describe '#call without session' do
    it 'returns session error' do
      executor = described_class.new(
        input: { 'questions' => [ { 'question' => 'Hello?', 'options' => [] } ] },
        config: {},
        agent: agent
      )
      result = executor.call
      expect(result).not_to be_success
      expect(result.error).to eq("Session required for ask_user tool")
    end
  end

  # ─── error handling ─────────────────────────────────────

  describe '#call when ActionCable raises' do
    before do
      allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError.new("Connection failed"))
      allow(Rails.cache).to receive(:write)
      allow(Rails.cache).to receive(:delete)
    end

    it 'cleans up Redis and returns error' do
      executor = make_executor(
        'questions' => [ { 'question' => 'Hello?', 'options' => [] } ]
      )
      result = executor.call
      expect(result).not_to be_success
      expect(result.error).to include("Ask user failed: Connection failed")
      expect(Rails.cache).to have_received(:delete).with("ask_user_pending:#{session.id}")
    end
  end
end
