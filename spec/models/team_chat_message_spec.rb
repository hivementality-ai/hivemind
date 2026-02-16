# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamChatMessage, type: :model do
  describe 'associations' do
    it { should belong_to(:team_chat_session) }
    it { should belong_to(:target_agent).class_name('Agent').optional }
  end

  describe 'validations' do
    it { should validate_presence_of(:content) }
    it { should validate_inclusion_of(:sender_type).in_array(%w[user agent]) }

    it 'validates presence of team_chat_session_id' do
      message = build(:team_chat_message, team_chat_session: nil)
      expect(message).not_to be_valid
      expect(message.errors[:team_chat_session]).to be_present
    end
  end

  describe 'scopes' do
    let(:session) { create(:team_chat_session) }
    let!(:msg1) { create(:team_chat_message, team_chat_session: session, created_at: 1.hour.ago) }
    let!(:msg2) { create(:team_chat_message, team_chat_session: session, created_at: 30.minutes.ago) }
    let!(:msg3) { create(:team_chat_message, team_chat_session: session, created_at: Time.current) }

    describe '.chronological' do
      it 'returns messages ordered by created_at ascending' do
        result = TeamChatMessage.chronological
        expect(result).to eq([ msg1, msg2, msg3 ])
      end
    end
  end

  describe '#from_user?' do
    it 'returns true when sender_type is user' do
      message = build(:team_chat_message, sender_type: "user")
      expect(message.from_user?).to be true
    end

    it 'returns false when sender_type is agent' do
      message = build(:team_chat_message, sender_type: "agent")
      expect(message.from_user?).to be false
    end
  end

  describe '#from_agent?' do
    it 'returns true when sender_type is agent' do
      message = build(:team_chat_message, sender_type: "agent")
      expect(message.from_agent?).to be true
    end

    it 'returns false when sender_type is user' do
      message = build(:team_chat_message, sender_type: "user")
      expect(message.from_agent?).to be false
    end
  end

  describe '#sender' do
    context 'when message is from user' do
      let(:user) { create(:user) }
      let(:message) do
        build(:team_chat_message,
              sender_type: "user",
              sender_id: user.id)
      end

      it 'returns the User' do
        expect(message.sender).to eq(user)
      end
    end

    context 'when message is from agent' do
      let(:agent) { create(:agent) }
      let(:message) do
        build(:team_chat_message,
              sender_type: "agent",
              sender_id: agent.id)
      end

      it 'returns the Agent' do
        expect(message.sender).to eq(agent)
      end
    end

    context 'when sender does not exist' do
      let(:message) do
        build(:team_chat_message,
              sender_type: "user",
              sender_id: 99_999)
      end

      it 'returns nil' do
        expect(message.sender).to be_nil
      end
    end
  end

  describe '.extract_mentions' do
    let!(:team) { create(:team) }
    let!(:agent1) { create(:agent, team: team, name: "Alice", enabled: true) }
    let!(:agent2) { create(:agent, team: team, name: "Bob", enabled: false) }
    let!(:agent3) { create(:agent, team: team, name: "Charlie", enabled: true) }

    context 'when text has @team mention' do
      it 'returns all enabled agents' do
        result = TeamChatMessage.extract_mentions("Hey @team, please help", team.reload)
        expect(result[:agents]).to match_array([ agent1, agent3 ])
        expect(result[:broadcast]).to be true
      end
    end

    context 'when text has specific agent mentions' do
      it 'returns mentioned agents' do
        result = TeamChatMessage.extract_mentions("@Alice and @Bob, please respond", team.reload)
        expect(result[:agents]).to match_array([ agent1, agent2 ])
        expect(result[:broadcast]).to be false
      end

      it 'returns mentioned disabled agents' do
        result = TeamChatMessage.extract_mentions("@Bob help", team.reload)
        expect(result[:agents]).to include(agent2)
      end
    end

    context 'when text has no mentions' do
      it 'returns empty agents array' do
        result = TeamChatMessage.extract_mentions("Just a regular message", team.reload)
        expect(result[:agents]).to be_empty
        expect(result[:broadcast]).to be false
      end
    end

    context 'when text has @god mention' do
      it 'sets god flag' do
        result = TeamChatMessage.extract_mentions("@god can you help?", team.reload)
        expect(result[:god]).to be true
      end
    end

    context 'when text has partial matches' do
      it 'does not match partial agent names' do
        create(:agent, team: team, name: "AliceLonger", enabled: true)
        result = TeamChatMessage.extract_mentions("Hello @Alice", team.reload)
        expect(result[:agents]).to eq([ agent1 ])
      end
    end

    context 'when text has case variations' do
      it 'matches mentions case-insensitively' do
        result = TeamChatMessage.extract_mentions("Hey @ALICE and @bob", team.reload)
        expect(result[:agents]).to match_array([ agent1, agent2 ])
      end
    end

    context 'when text has multiple mentions of same agent' do
      it 'returns unique agents' do
        result = TeamChatMessage.extract_mentions("@Alice please @Alice respond", team.reload)
        expect(result[:agents].count).to eq(1)
        expect(result[:agents]).to include(agent1)
      end
    end
  end

  describe 'factory' do
    it 'creates a valid message' do
      expect(build(:team_chat_message)).to be_valid
    end

    it 'creates valid messages with traits' do
      expect(build(:team_chat_message, :from_user)).to be_valid
      expect(build(:team_chat_message, :from_agent)).to be_valid
      expect(build(:team_chat_message, :team_broadcast)).to be_valid
    end
  end
end
