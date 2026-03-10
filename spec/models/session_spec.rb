# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Session, type: :model do
  describe 'associations' do
    it { should belong_to(:agent) }
    it { should have_many(:transcript_archives).dependent(:destroy) }
    it { should have_many(:usage_records).dependent(:destroy) }
    it { should have_many(:chat_attachments).dependent(:destroy) }
    it { should have_many(:tool_executions).dependent(:destroy) }
    it { should have_many(:coding_agent_tasks).dependent(:destroy) }
    it { should have_many(:research_sessions).dependent(:destroy) }
    it { should have_many(:heartbeat_runs).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:session_key) }

    it 'validates uniqueness of session_key' do
      create(:session, session_key: "unique_key")
      expect(build(:session, session_key: "unique_key")).not_to be_valid
    end
  end

  describe 'enums' do
    it { should define_enum_for(:status).with_values(active: 0, completed: 1, archived: 2, expired: 3).with_default(:active) }
  end

  describe 'scopes' do
    let!(:active_session) { create(:session, :active) }
    let!(:completed_session) { create(:session, :completed) }
    let!(:recent_session) { create(:session, last_activity_at: 1.hour.ago) }
    let!(:old_session) { create(:session, last_activity_at: 48.hours.ago) }

    describe '.active_sessions' do
      it 'returns only active sessions' do
        expect(Session.active_sessions).to include(active_session)
        expect(Session.active_sessions).not_to include(completed_session)
      end
    end

    describe '.recent' do
      it 'returns sessions with activity in last 24 hours' do
        expect(Session.recent).to include(recent_session)
        expect(Session.recent).not_to include(old_session)
      end
    end
  end

  describe 'default values' do
    let(:session) { Session.new }

    it 'initializes transcript as empty array' do
      expect(session.transcript).to eq([])
    end

    it 'initializes metadata as empty hash' do
      expect(session.metadata).to eq({})
    end

    it 'initializes input_tokens to 0' do
      expect(session.input_tokens).to eq(0)
    end

    it 'initializes output_tokens to 0' do
      expect(session.output_tokens).to eq(0)
    end

    it 'initializes total_tokens to 0' do
      expect(session.total_tokens).to eq(0)
    end
  end

  describe '#append_transcript' do
    let(:session) { create(:session) }
    let(:entry) { { role: "user", content: "Hello" } }

    it 'adds entry to transcript with timestamp' do
      expect {
        session.append_transcript(entry)
      }.to change { session.transcript.size }.by(1)

      last_entry = session.transcript.last
      expect(last_entry["role"]).to eq("user")
      expect(last_entry["content"]).to eq("Hello")
      expect(last_entry["timestamp"]).to be_present
    end

    it 'updates last_activity_at' do
      original_time = session.last_activity_at
      sleep 0.01
      session.append_transcript(entry)
      expect(session.last_activity_at).to be > original_time
    end

    it 'saves the session' do
      session.append_transcript(entry)
      session.reload
      expect(session.transcript.size).to eq(1)
    end
  end

  describe '#transcript_size' do
    it 'returns 0 for empty transcript' do
      session = create(:session, transcript: [])
      expect(session.transcript_size).to eq(0)
    end

    it 'returns count of transcript entries' do
      session = create(:session, :with_transcript)
      expect(session.transcript_size).to eq(2)
    end

    it 'handles nil transcript' do
      session = Session.new(session_key: "test", agent: create(:agent))
      session.transcript = nil
      expect(session.transcript_size).to eq(0)
    end
  end

  describe '#transcript_summary' do
    let(:session) { create(:session, :with_transcript, input_tokens: 100, output_tokens: 50, total_tokens: 150) }

    it 'returns summary hash' do
      summary = session.transcript_summary

      expect(summary[:total_entries]).to eq(2)
      expect(summary[:first_entry_at]).to be_present
      expect(summary[:last_entry_at]).to be_present
      expect(summary[:input_tokens]).to eq(100)
      expect(summary[:output_tokens]).to eq(50)
      expect(summary[:total_tokens]).to eq(150)
    end
  end

  describe '#key' do
    it 'returns session_key as alias' do
      session = create(:session, session_key: "test_key")
      expect(session.key).to eq("test_key")
    end
  end

  describe 'factory' do
    it 'creates a valid session' do
      expect(build(:session)).to be_valid
    end

    it 'creates valid sessions with traits' do
      expect(build(:session, :active)).to be_valid
      expect(build(:session, :completed)).to be_valid
      expect(build(:session, :archived)).to be_valid
      expect(build(:session, :expired)).to be_valid
      expect(build(:session, :with_transcript)).to be_valid
    end
  end

  describe 'cascade destruction' do
    let(:agent) { create(:agent) }
    let(:session) { create(:session, agent: agent) }

    it 'destroys tool_executions when session is destroyed' do
      tool_execution = create(:tool_execution, session: session)
      expect {
        session.destroy
      }.to change(ToolExecution, :count).by(-1)
      expect(ToolExecution.exists?(tool_execution.id)).to be(false)
    end

    it 'destroys coding_agent_tasks when session is destroyed' do
      coding_task = create(:coding_agent_task, session: session)
      expect {
        session.destroy
      }.to change(CodingAgentTask, :count).by(-1)
      expect(CodingAgentTask.exists?(coding_task.id)).to be(false)
    end

    it 'destroys research_sessions when session is destroyed' do
      research = create(:research_session, session: session)
      expect {
        session.destroy
      }.to change(ResearchSession, :count).by(-1)
      expect(ResearchSession.exists?(research.id)).to be(false)
    end

    it 'destroys heartbeat_runs when session is destroyed' do
      heartbeat = create(:heartbeat_run, session: session)
      expect {
        session.destroy
      }.to change(HeartbeatRun, :count).by(-1)
      expect(HeartbeatRun.exists?(heartbeat.id)).to be(false)
    end

    it 'nullifies sub_agent_tasks parent_session_id when session is destroyed' do
      sub_task = create(:sub_agent_task, parent_session: session)
      session.destroy
      expect(sub_task.reload.parent_session_id).to be_nil
    end

    it 'nullifies sub_agent_tasks child_session_id when session is destroyed' do
      sub_task = create(:sub_agent_task, child_session: session)
      session.destroy
      expect(sub_task.reload.child_session_id).to be_nil
    end
  end
end
