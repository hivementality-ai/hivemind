# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamChatSession, type: :model do
  describe 'associations' do
    it { should belong_to(:team) }
    it { should belong_to(:user) }
    it { should have_many(:team_chat_messages).dependent(:destroy) }
    it { should have_many(:agent_sessions).class_name('Session').dependent(:nullify) }
  end

  describe 'validations' do
    describe 'uniqueness of session_key' do
      let!(:existing_session) { create(:team_chat_session, session_key: SecureRandom.uuid) }

      it 'rejects duplicate session_keys' do
        new_session = build(:team_chat_session, session_key: existing_session.session_key)
        expect(new_session).not_to be_valid
        expect(new_session.errors[:session_key]).to include('has already been taken')
      end
    end

    it 'validates presence of team_id' do
      session = build(:team_chat_session, team: nil)
      expect(session).not_to be_valid
      expect(session.errors[:team]).to be_present
    end

    it 'validates presence of user_id' do
      session = build(:team_chat_session, user: nil)
      expect(session).not_to be_valid
      expect(session.errors[:user]).to be_present
    end
  end

  describe 'enums' do
    it { should define_enum_for(:status).with_values(active: 0, archived: 1).with_default(:active) }
  end

  describe 'scopes' do
    let!(:active_session) { create(:team_chat_session, status: :active) }
    let!(:archived_session) { create(:team_chat_session, status: :archived) }

    describe '.recent' do
      it 'returns sessions ordered by updated_at descending' do
        # Update one session to make it more recent
        active_session.update(updated_at: 1.hour.ago)
        archived_session.update(updated_at: Time.current)

        result = TeamChatSession.recent
        expect(result.first).to eq(archived_session)
        expect(result.last).to eq(active_session)
      end
    end
  end

  describe '#generate_session_key' do
    let(:session) { build(:team_chat_session, session_key: nil) }

    it 'generates session_key on create' do
      session.save!
      expect(session.session_key).to be_present
      expect(session.session_key).to match(/^[0-9a-f\-]{36}$/)
    end

    it 'does not overwrite existing session_key' do
      custom_key = "custom-key-12345"
      session.session_key = custom_key
      session.save!
      expect(session.session_key).to eq(custom_key)
    end
  end

  describe '#recent_messages' do
    let(:session) { create(:team_chat_session) }

    before do
      create_list(:team_chat_message, 60, team_chat_session: session)
    end

    it 'returns the last 50 messages by default' do
      messages = session.recent_messages
      expect(messages.count).to eq(50)
    end

    it 'respects the limit parameter' do
      messages = session.recent_messages(limit: 10)
      expect(messages.count).to eq(10)
    end

    it 'returns messages in chronological order' do
      messages = session.recent_messages(limit: 5)
      expect(messages).to eq(messages.sort_by(&:created_at))
    end
  end

  describe '#session_for' do
    let(:session) { create(:team_chat_session) }
    let(:agent) { create(:agent, team: session.team) }

    context 'when no session exists for the agent' do
      it 'creates a new session' do
        expect {
          session.session_for(agent)
        }.to change(Session, :count).by(1)
      end

      it 'returns a Session with correct attributes' do
        result = session.session_for(agent)

        expect(result).to be_a(Session)
        expect(result.agent).to eq(agent)
        expect(result.team_chat_session).to eq(session)
        expect(result.status).to eq('active')
      end

      it 'sets the session key correctly' do
        result = session.session_for(agent)

        expect(result.session_key).to match(/^tc-#{Regexp.escape(session.session_key)}-#{agent.id}$/)
      end

      it 'includes metadata' do
        result = session.session_for(agent)

        expect(result.metadata).to be_a(Hash)
        expect(result.metadata).to include('team_chat_session_id' => session.id, 'team_id' => session.team_id)
      end
    end

    context 'when session already exists for the agent' do
      let!(:existing_session) do
        create(:session, agent: agent, team_chat_session: session)
      end

      it 'returns the existing session' do
        result = session.session_for(agent)
        expect(result).to eq(existing_session)
      end

      it 'does not create a new session' do
        expect {
          session.session_for(agent)
        }.not_to change(Session, :count)
      end
    end
  end

  describe 'factory' do
    it 'creates a valid session' do
      expect(build(:team_chat_session)).to be_valid
    end

    it 'creates valid sessions with traits' do
      expect(build(:team_chat_session, :archived)).to be_valid
      expect(build(:team_chat_session, :with_messages)).to be_valid
      expect(build(:team_chat_session, :with_agent_sessions)).to be_valid
    end
  end
end
