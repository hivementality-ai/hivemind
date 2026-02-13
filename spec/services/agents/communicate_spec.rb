# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Agents::Communicate do
  describe '.call' do
    let(:team) { create(:team) }
    let(:from_agent) { create(:agent, team: team) }
    let(:content) { "Hello team!" }

    before do
      # Mock ActionCable
      allow(ActionCable.server).to receive(:broadcast)
    end

    context 'when broadcasting to team' do
      it 'creates a team message successfully' do
        expect {
          described_class.call(from_agent: from_agent, content: content, team: team)
        }.to change(TeamMessage, :count).by(1)

        message = TeamMessage.last
        expect(message.team_id).to eq(team.id)
        expect(message.from_agent_id).to eq(from_agent.id)
        expect(message.to_agent_id).to be_nil
        expect(message.message_type).to eq("broadcast")
        expect(message.content).to eq(content)
      end

      it 'returns success with message data' do
        result = described_class.call(from_agent: from_agent, content: content, team: team)

        expect(result).to be_a(ServiceResponse)
        expect(result.success?).to be true
        expect(result.data[:message]).to be_a(TeamMessage)
        expect(result.data[:message].content).to eq(content)
      end

      it 'broadcasts the message via ActionCable' do
        expect(ActionCable.server).to receive(:broadcast).with(
          "team_#{team.id}",
          hash_including(
            type: "team_message",
            message: hash_including(
              from_agent: hash_including(
                id: from_agent.id,
                name: from_agent.name,
                role: from_agent.role
              ),
              to_agent: nil,
              content: content,
              message_type: "broadcast"
            )
          )
        )

        described_class.call(from_agent: from_agent, content: content, team: team)
      end
    end

    context 'when sending direct message' do
      let(:to_agent) { create(:agent, team: team) }

      it 'creates a direct team message' do
        result = described_class.call(
          from_agent: from_agent,
          content: content,
          team: team,
          to_agent: to_agent
        )

        expect(result.success?).to be true
        message = result.data[:message]
        expect(message.to_agent_id).to eq(to_agent.id)
        expect(message.message_type).to eq("direct")
      end

      it 'includes to_agent in broadcast' do
        expect(ActionCable.server).to receive(:broadcast).with(
          "team_#{team.id}",
          hash_including(
            message: hash_including(
              to_agent: hash_including(
                id: to_agent.id,
                name: to_agent.name
              )
            )
          )
        )

        described_class.call(
          from_agent: from_agent,
          content: content,
          team: team,
          to_agent: to_agent
        )
      end
    end

    context 'when agent is not on team' do
      let(:other_team) { create(:team) }
      let(:other_agent) { create(:agent, team: other_team) }

      it 'returns failure' do
        result = described_class.call(
          from_agent: other_agent,
          content: content,
          team: team
        )

        expect(result.success?).to be false
        expect(result.error).to eq("Agent must be on the specified team")
      end

      it 'does not create a message' do
        expect {
          described_class.call(
            from_agent: other_agent,
            content: content,
            team: team
          )
        }.not_to change(TeamMessage, :count)
      end

      it 'does not broadcast' do
        expect(ActionCable.server).not_to receive(:broadcast)

        described_class.call(
          from_agent: other_agent,
          content: content,
          team: team
        )
      end
    end

    context 'when message creation fails' do
      before do
        allow(TeamMessage).to receive(:create).and_return(
          double(persisted?: false, errors: double(full_messages: ["Content can't be blank"]))
        )
      end

      it 'returns failure with error messages' do
        result = described_class.call(from_agent: from_agent, content: content, team: team)

        expect(result.success?).to be false
        expect(result.error).to eq(["Content can't be blank"])
      end
    end

    context 'when an exception occurs' do
      before do
        allow(TeamMessage).to receive(:create).and_raise(StandardError, "Database error")
      end

      it 'returns failure with error message' do
        result = described_class.call(from_agent: from_agent, content: content, team: team)

        expect(result.success?).to be false
        expect(result.error).to eq("Communication failed: Database error")
      end
    end
  end
end