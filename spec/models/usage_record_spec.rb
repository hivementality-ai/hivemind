# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UsageRecord, type: :model do
  describe 'associations' do
    it { should belong_to(:agent) }
    it { should belong_to(:session).optional }
  end

  describe 'validations' do
    it { should validate_presence_of(:provider) }
  end

  describe 'scopes' do
    let!(:recent_record) { create(:usage_record, created_at: 1.hour.ago) }
    let!(:old_record) { create(:usage_record, created_at: 48.hours.ago) }
    let!(:period_record) { create(:usage_record, created_at: 2.days.ago) }

    describe '.recent' do
      it 'returns records from last 24 hours' do
        expect(UsageRecord.recent).to include(recent_record)
        expect(UsageRecord.recent).not_to include(old_record)
      end
    end

    describe '.for_period' do
      it 'returns records within specified period' do
        start_time = 3.days.ago
        end_time = 1.day.ago
        records = UsageRecord.for_period(start_time, end_time)
        expect(records).to include(period_record)
        expect(records).not_to include(recent_record)
      end
    end
  end

  describe '#total_tokens' do
    it 'returns sum of input and output tokens' do
      record = build(:usage_record, input_tokens: 100, output_tokens: 50)
      expect(record.total_tokens).to eq(150)
    end

    it 'handles nil values' do
      record = build(:usage_record, input_tokens: nil, output_tokens: nil)
      expect(record.total_tokens).to eq(0)
    end
  end

  describe 'default values' do
    let(:record) { UsageRecord.new }

    it 'initializes input_tokens to 0' do
      expect(record.input_tokens).to eq(0)
    end

    it 'initializes output_tokens to 0' do
      expect(record.output_tokens).to eq(0)
    end

    it 'initializes cache_tokens to 0' do
      expect(record.cache_tokens).to eq(0)
    end

    it 'initializes cost_cents to 0' do
      expect(record.cost_cents).to eq(0)
    end

    it 'initializes metadata as empty hash' do
      expect(record.metadata).to eq({})
    end
  end

  describe 'factory' do
    it 'creates a valid usage record' do
      expect(build(:usage_record)).to be_valid
    end

    it 'creates valid records with traits' do
      expect(build(:usage_record, :anthropic)).to be_valid
      expect(build(:usage_record, :ollama)).to be_valid
      expect(build(:usage_record, :expensive)).to be_valid
      expect(build(:usage_record, :no_session)).to be_valid
    end
  end
end
