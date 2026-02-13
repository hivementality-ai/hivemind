# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamMessage, type: :model do
  describe 'associations' do
    it { should belong_to(:from_agent).class_name('Agent') }
    it { should belong_to(:to_agent).class_name('Agent').optional }
    it { should belong_to(:team) }
  end

  describe 'validations' do
    it { should validate_presence_of(:content) }
  end

  describe 'scopes' do
    let(:team) { create(:team) }
    let(:other_team) { create(:team) }
    let!(:recent_message) { create(:team_message, team: team, created_at: 1.hour.ago) }
    let!(:old_message) { create(:team_message, team: team, created_at: 1.week.ago) }
    let!(:broadcast_message) { create(:team_message, :broadcast, team: team) }
    let!(:direct_message) { create(:team_message, :direct_message, team: team) }
    let!(:other_team_message) { create(:team_message, team: other_team) }

    describe '.recent' do
      it 'returns messages ordered by created_at desc' do
        messages = TeamMessage.recent
        expect(messages.first.created_at).to be > messages.last.created_at
      end
    end

    describe '.for_team' do
      it 'returns messages for specific team' do
        messages = TeamMessage.for_team(team)
        expect(messages).to include(recent_message, old_message, broadcast_message, direct_message)
        expect(messages).not_to include(other_team_message)
      end
    end

    describe '.broadcast_messages' do
      it 'returns only broadcast messages' do
        messages = TeamMessage.broadcast_messages
        expect(messages).to include(broadcast_message)
        expect(messages).not_to include(direct_message)
      end
    end
  end

  describe 'default values' do
    let(:message) { TeamMessage.new }

    it 'initializes metadata as empty hash' do
      expect(message.metadata).to eq({})
    end

    it 'initializes message_type to chat' do
      expect(message.message_type).to eq("chat")
    end
  end

  describe 'factory' do
    it 'creates a valid team message' do
      expect(build(:team_message)).to be_valid
    end

    it 'creates valid messages with traits' do
      expect(build(:team_message, :direct_message)).to be_valid
      expect(build(:team_message, :broadcast)).to be_valid
      expect(build(:team_message, :system_message)).to be_valid
      expect(build(:team_message, :task_message)).to be_valid
    end
  end
end
