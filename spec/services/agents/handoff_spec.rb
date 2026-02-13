# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Agents::Handoff do
  describe '.call' do
    let(:team) { create(:team) }
    let(:from_agent) { create(:agent, team: team, name: "Assistant", role: "assistant") }
    let(:to_agent) { create(:agent, team: team, name: "Expert", role: "specialist") }
    let(:session) { create(:session, agent: from_agent, status: "active", transcript: sample_transcript) }
    let(:context_summary) { "User was asking about database performance issues" }

    let(:sample_transcript) do
      [
        { "role" => "user", "content" => "I need help with database performance" },
        { "role" => "assistant", "content" => "I can help you with basic queries, but you might need a specialist" },
        { "role" => "user", "content" => "Yes, can you connect me with someone who knows more?" }
      ]
    end

    before do
      # Mock external dependencies
      allow(ActionCable.server).to receive(:broadcast)
      allow(Audit::Log).to receive(:call)
      allow(SecureRandom).to receive(:hex).with(16).and_return("abc123def456")
    end

    describe 'successful handoff' do
      it 'updates original session status to handed_off' do
        result = described_class.call(
          from_agent: from_agent,
          to_agent: to_agent,
          session: session,
          context_summary: context_summary
        )

        expect(result.success?).to be true
        session.reload
        expect(session.status).to eq("handed_off")
        expect(session.metadata["handed_off_to"]).to eq(to_agent.id)
        expect(session.metadata["handed_off_at"]).to be_present
      end

      it 'creates new session for target agent' do
        expect {
          described_class.call(
            from_agent: from_agent,
            to_agent: to_agent,
            session: session,
            context_summary: context_summary
          )
        }.to change(Session, :count).by(1)

        new_session = Session.last
        expect(new_session.agent).to eq(to_agent)
        expect(new_session.key).to eq("session_abc123def456")
        expect(new_session.status).to eq("active")
        expect(new_session.metadata["handed_off_from"]).to eq(from_agent.id)
        expect(new_session.metadata["original_session_id"]).to eq(session.id)
        expect(new_session.metadata["handoff_at"]).to be_present
      end

      it 'includes context message in new session transcript' do
        result = described_class.call(
          from_agent: from_agent,
          to_agent: to_agent,
          session: session,
          context_summary: context_summary
        )

        new_session = result.data[:new_session]
        context_message = new_session.transcript.first

        expect(context_message["role"]).to eq("system")
        expect(context_message["content"]).to include("handed off from Assistant (assistant)")
        expect(context_message["content"]).to include(context_summary)
        expect(context_message["content"]).to include("Continue this conversation as specialist")
        expect(context_message["timestamp"]).to be_present
      end

      it 'creates team message when agents are on same team' do
        expect {
          described_class.call(
            from_agent: from_agent,
            to_agent: to_agent,
            session: session,
            context_summary: context_summary
          )
        }.to change(TeamMessage, :count).by(1)

        team_message = TeamMessage.last
        expect(team_message.team_id).to eq(team.id)
        expect(team_message.agent).to eq(from_agent)
        expect(team_message.message_type).to eq("handoff")
        expect(team_message.content).to include("Handed off conversation to Expert")
        expect(team_message.metadata["from_agent_id"]).to eq(from_agent.id)
        expect(team_message.metadata["to_agent_id"]).to eq(to_agent.id)
      end

      it 'broadcasts handoff to mission control' do
        expect(ActionCable.server).to receive(:broadcast).with(
          "mission_control_channel",
          hash_including(
            type: "conversation_handoff",
            from_agent_id: from_agent.id,
            from_agent_name: from_agent.name,
            to_agent_id: to_agent.id,
            to_agent_name: to_agent.name,
            original_session_id: session.id,
            timestamp: be_present
          )
        )

        described_class.call(
          from_agent: from_agent,
          to_agent: to_agent,
          session: session,
          context_summary: context_summary
        )
      end

      it 'creates audit log entry' do
        expect(Audit::Log).to receive(:call).with(
          actor: from_agent.name,
          action: "conversation.handoff",
          resource: session,
          metadata: {
            from_agent_id: from_agent.id,
            to_agent_id: to_agent.id,
            new_session_id: be_a(Integer),
            context_summary: context_summary
          }
        )

        described_class.call(
          from_agent: from_agent,
          to_agent: to_agent,
          session: session,
          context_summary: context_summary
        )
      end

      it 'returns success with session data' do
        result = described_class.call(
          from_agent: from_agent,
          to_agent: to_agent,
          session: session,
          context_summary: context_summary
        )

        expect(result).to be_a(ServiceResponse)
        expect(result.success?).to be true
        expect(result.data[:original_session]).to eq(session)
        expect(result.data[:new_session]).to be_a(Session)
        expect(result.data[:to_agent]).to eq(to_agent)
      end
    end

    describe 'without context summary' do
      it 'extracts conversation summary from transcript' do
        result = described_class.call(
          from_agent: from_agent,
          to_agent: to_agent,
          session: session
        )

        new_session = result.data[:new_session]
        context_message = new_session.transcript.first

        expect(context_message["content"]).to include("user: I need help with database performance")
        expect(context_message["content"]).to include("assistant: I can help you with basic queries")
      end

      it 'handles empty transcript gracefully' do
        empty_session = create(:session, agent: from_agent, transcript: [])

        result = described_class.call(
          from_agent: from_agent,
          to_agent: to_agent,
          session: empty_session
        )

        new_session = result.data[:new_session]
        context_message = new_session.transcript.first

        expect(context_message["content"]).to include("No prior context")
      end

      it 'handles non-array transcript' do
        invalid_session = create(:session, agent: from_agent, transcript: "invalid")

        result = described_class.call(
          from_agent: from_agent,
          to_agent: to_agent,
          session: invalid_session
        )

        new_session = result.data[:new_session]
        context_message = new_session.transcript.first

        expect(context_message["content"]).to include("No prior context")
      end
    end

    describe 'team message creation' do
      context 'when agents are on different teams' do
        let(:other_team) { create(:team) }
        let(:other_agent) { create(:agent, team: other_team) }

        it 'does not create team message' do
          expect {
            described_class.call(
              from_agent: from_agent,
              to_agent: other_agent,
              session: session
            )
          }.not_to change(TeamMessage, :count)
        end
      end

      context 'when from_agent has no team' do
        let(:teamless_agent) { create(:agent, team: nil) }

        it 'does not create team message' do
          expect {
            described_class.call(
              from_agent: teamless_agent,
              to_agent: to_agent,
              session: session
            )
          }.not_to change(TeamMessage, :count)
        end
      end
    end

    describe 'error handling' do
      context 'when session update fails' do
        before do
          allow(session).to receive(:update!).and_raise(ActiveRecord::RecordInvalid, "Validation failed")
        end

        it 'returns failure and rolls back transaction' do
          result = described_class.call(
            from_agent: from_agent,
            to_agent: to_agent,
            session: session
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Handoff failed: Validation failed")
          expect(Session.count).to eq(1) # No new session created
        end
      end

      context 'when new session creation fails' do
        before do
          allow(Session).to receive(:create!).and_raise(ActiveRecord::RecordInvalid, "Key already exists")
        end

        it 'returns failure and rolls back all changes' do
          original_status = session.status
          result = described_class.call(
            from_agent: from_agent,
            to_agent: to_agent,
            session: session
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Handoff failed: Key already exists")
          
          # Original session should be unchanged due to transaction rollback
          session.reload
          expect(session.status).to eq(original_status)
        end
      end

      context 'when audit logging fails' do
        before do
          allow(Audit::Log).to receive(:call).and_raise(StandardError, "Audit system unavailable")
        end

        it 'returns failure and rolls back all changes' do
          result = described_class.call(
            from_agent: from_agent,
            to_agent: to_agent,
            session: session
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Handoff failed: Audit system unavailable")
        end
      end
    end
  end
end