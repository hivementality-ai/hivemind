# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Agents::Delegate do
  describe '.call' do
    let(:team) { create(:team) }
    let(:from_agent) { create(:agent, team: team) }
    let(:to_agent) { create(:agent, team: team) }
    let(:task) { "Please analyze the quarterly sales data and provide insights" }
    let(:context) { { priority: "high", deadline: "2024-02-20" } }

    describe 'successful delegation' do
      it 'creates a delegation team message' do
        expect {
          described_class.call(
            from_agent: from_agent,
            to_agent: to_agent,
            task: task,
            context: context
          )
        }.to change(TeamMessage, :count).by(1)

        message = TeamMessage.last
        expect(message.team_id).to eq(team.id)
        expect(message.from_agent_id).to eq(from_agent.id)
        expect(message.to_agent_id).to eq(to_agent.id)
        expect(message.message_type).to eq("delegation")
        expect(message.content).to eq(task)
        expect(message.metadata["context"]).to eq(context.stringify_keys)
      end

      it 'returns success with message and task data' do
        result = described_class.call(
          from_agent: from_agent,
          to_agent: to_agent,
          task: task
        )

        expect(result).to be_a(ServiceResponse)
        expect(result.success?).to be true
        expect(result.data[:message]).to be_a(TeamMessage)
        expect(result.data[:task]).to eq(task)
      end

      it 'enqueues an AgentTaskJob' do
        expect {
          described_class.call(
            from_agent: from_agent,
            to_agent: to_agent,
            task: task
          )
        }.to change { Sidekiq::Job.jobs.size }.by(1)

        job = Sidekiq::Job.jobs.last
        expect(job['class']).to eq('AgentTaskJob')
        expect(job['args']).to eq([to_agent.id, TeamMessage.last.id])
      end

      it 'works without context' do
        result = described_class.call(
          from_agent: from_agent,
          to_agent: to_agent,
          task: task
        )

        expect(result.success?).to be true
        message = result.data[:message]
        expect(message.metadata).to eq({})
      end
    end

    describe 'validation failures' do
      context 'when agent tries to delegate to itself' do
        it 'returns failure' do
          result = described_class.call(
            from_agent: from_agent,
            to_agent: from_agent,
            task: task
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Agent cannot delegate to itself")
        end

        it 'does not create a message or enqueue job' do
          expect {
            described_class.call(
              from_agent: from_agent,
              to_agent: from_agent,
              task: task
            )
          }.not_to change(TeamMessage, :count)

          expect(Sidekiq::Job.jobs).to be_empty
        end
      end

      context 'when agents are on different teams' do
        let(:other_team) { create(:team) }
        let(:other_agent) { create(:agent, team: other_team) }

        it 'returns failure' do
          result = described_class.call(
            from_agent: from_agent,
            to_agent: other_agent,
            task: task
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Agents must be on the same team")
        end

        it 'does not create a message or enqueue job' do
          expect {
            described_class.call(
              from_agent: from_agent,
              to_agent: other_agent,
              task: task
            )
          }.not_to change(TeamMessage, :count)

          expect(Sidekiq::Job.jobs).to be_empty
        end
      end

      context 'when from_agent has no team' do
        let(:teamless_agent) { create(:agent, team: nil) }

        it 'returns failure' do
          result = described_class.call(
            from_agent: teamless_agent,
            to_agent: to_agent,
            task: task
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Agents must be on the same team")
        end
      end
    end

    describe 'message creation failures' do
      before do
        allow(TeamMessage).to receive(:create).and_return(
          double(persisted?: false, errors: double(full_messages: ["Content can't be blank"]))
        )
      end

      it 'returns failure with error messages' do
        result = described_class.call(
          from_agent: from_agent,
          to_agent: to_agent,
          task: task
        )

        expect(result.success?).to be false
        expect(result.error).to eq(["Content can't be blank"])
      end

      it 'does not enqueue job when message creation fails' do
        expect {
          described_class.call(
            from_agent: from_agent,
            to_agent: to_agent,
            task: task
          )
        }.not_to change { Sidekiq::Job.jobs.size }
      end
    end

    describe 'exception handling' do
      before do
        allow(TeamMessage).to receive(:create).and_raise(StandardError, "Database connection lost")
      end

      it 'returns failure with error message' do
        result = described_class.call(
          from_agent: from_agent,
          to_agent: to_agent,
          task: task
        )

        expect(result.success?).to be false
        expect(result.error).to eq("Delegation failed: Database connection lost")
      end
    end
  end
end