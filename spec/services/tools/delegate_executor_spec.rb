# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::DelegateExecutor, type: :service do
  let(:delegating_agent) { create(:agent, name: 'Main Agent') }
  let(:executor) { described_class.new(input: input, config: {}, agent: delegating_agent) }

  describe '#call' do
    context 'with valid delegation' do
      let(:target_agent) { create(:agent, name: 'Helper Agent', visible: true, enabled: true) }
      let(:input) { { "agent" => "Helper Agent", "task" => "Generate a summary report" } }

      before do
        allow(Sessions::Chat).to receive(:call).and_return(
          ServiceResponse.success(data: { reply: "Here's your summary report with key metrics..." })
        )
      end

      it 'returns success with agent response' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Helper Agent responded:")
        expect(result.data[:output]).to include("Here's your summary report")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'creates or finds delegation session' do
        expect {
          executor.call
        }.to change(Session, :count).by(1)

        session = Session.last
        expect(session.agent).to eq(target_agent)
        expect(session.title).to eq("📋 Delegated by Main Agent")
        expect(session.session_key).to eq("delegate-#{target_agent.id}-#{delegating_agent.id}")
        expect(session.status).to eq("active")
        expect(session.metadata["type"]).to eq("delegation")
        expect(session.metadata["delegated_by"]).to eq("Main Agent")
      end

      it 'calls Sessions::Chat with correct parameters' do
        executor.call
        session = Session.last
        expect(Sessions::Chat).to have_received(:call).with(
          session: session,
          message: "Generate a summary report",
          agent: target_agent
        )
      end

      context 'when delegation session already exists' do
        before do
          create(:session,
            agent: target_agent,
            title: "📋 Delegated by Main Agent",
            session_key: "delegate-#{target_agent.id}-#{delegating_agent.id}"
          )
        end

        it 'reuses existing session' do
          expect {
            executor.call
          }.not_to change(Session, :count)
        end
      end

      context 'with case insensitive agent name' do
        let(:input) { { "agent" => "HELPER agent", "task" => "Do something" } }

        it 'finds agent regardless of case' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("Helper Agent responded:")
        end
      end

      context 'with long response' do
        before do
          long_response = 'x' * 4000
          allow(Sessions::Chat).to receive(:call).and_return(
            ServiceResponse.success(data: { reply: long_response })
          )
        end

        it 'truncates response to 3000 characters' do
          result = executor.call
          expect(result).to be_success
          response_part = result.data[:output].split("\n\n").last
          expect(response_part.length).to be <= 3000
        end
      end
    end

    context 'without agent name' do
      let(:input) { { "task" => "Do something" } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No agent name provided")
      end
    end

    context 'with empty agent name' do
      let(:input) { { "agent" => "  ", "task" => "Do something" } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No agent name provided")
      end
    end

    context 'without task' do
      let(:input) { { "agent" => "Helper Agent" } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No task provided")
      end
    end

    context 'with empty task' do
      let(:input) { { "agent" => "Helper Agent", "task" => "  " } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No task provided")
      end
    end

    context 'when target agent is not found' do
      let(:input) { { "agent" => "Nonexistent Agent", "task" => "Do something" } }

      before do
        create(:agent, name: 'Available Agent 1', visible: true, enabled: true)
        create(:agent, name: 'Available Agent 2', visible: true, enabled: true)
      end

      it 'returns failure with available agents' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Agent 'Nonexistent Agent' not found")
        expect(result.error).to include("Available Agent 1, Available Agent 2")
      end
    end

    context 'when target agent is not visible' do
      let(:target_agent) { create(:agent, name: 'Hidden Agent', visible: false, enabled: true) }
      let(:input) { { "agent" => "Hidden Agent", "task" => "Do something" } }

      it 'returns failure as if agent does not exist' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Agent 'Hidden Agent' not found")
      end
    end

    context 'when target agent is not enabled' do
      let(:target_agent) { create(:agent, name: 'Disabled Agent', visible: true, enabled: false) }
      let(:input) { { "agent" => "Disabled Agent", "task" => "Do something" } }

      it 'returns failure as if agent does not exist' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Agent 'Disabled Agent' not found")
      end
    end

    context 'when Sessions::Chat fails' do
      let(:target_agent) { create(:agent, name: 'Failing Agent', visible: true, enabled: true) }
      let(:input) { { "agent" => "Failing Agent", "task" => "Cause an error" } }

      before do
        allow(Sessions::Chat).to receive(:call).and_return(
          ServiceResponse.failure(error: "Model timeout")
        )
      end

      it 'returns failure with agent error' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Failing Agent failed: Model timeout")
      end
    end

    context 'when session creation fails' do
      let(:target_agent) { create(:agent, name: 'Target Agent', visible: true, enabled: true) }
      let(:input) { { "agent" => "Target Agent", "task" => "Test task" } }

      before do
        allow(Session).to receive(:find_or_create_by!).and_raise(ActiveRecord::RecordInvalid.new(Session.new))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Delegation failed:")
      end
    end

    context 'when delegating agent is nil' do
      let(:executor) { described_class.new(input: input, config: {}, agent: nil) }
      let(:target_agent) { create(:agent, name: 'Helper Agent', visible: true, enabled: true) }
      let(:input) { { "agent" => "Helper Agent", "task" => "System task" } }

      before do
        allow(Sessions::Chat).to receive(:call).and_return(
          ServiceResponse.success(data: { reply: "Task completed" })
        )
      end

      it 'handles system delegation' do
        result = executor.call
        expect(result).to be_success
        
        session = Session.last
        expect(session.title).to eq("📋 Delegated by System")
        expect(session.session_key).to eq("delegate-#{target_agent.id}-system")
        expect(session.metadata["delegated_by"]).to be_nil
      end
    end

    context 'with empty reply' do
      let(:target_agent) { create(:agent, name: 'Silent Agent', visible: true, enabled: true) }
      let(:input) { { "agent" => "Silent Agent", "task" => "Be quiet" } }

      before do
        allow(Sessions::Chat).to receive(:call).and_return(
          ServiceResponse.success(data: { reply: "" })
        )
      end

      it 'handles empty response' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Silent Agent responded:\n\n")
      end
    end

    context 'when Sessions::Chat returns nil reply' do
      let(:target_agent) { create(:agent, name: 'Null Agent', visible: true, enabled: true) }
      let(:input) { { "agent" => "Null Agent", "task" => "Return nothing" } }

      before do
        allow(Sessions::Chat).to receive(:call).and_return(
          ServiceResponse.success(data: { reply: nil })
        )
      end

      it 'handles nil response' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Null Agent responded:\n\n")
      end
    end
  end

  describe '#available_agents' do
    before do
      create(:agent, name: 'Agent 1', visible: true, enabled: true)
      create(:agent, name: 'Agent 2', visible: true, enabled: true)
      create(:agent, name: 'Hidden Agent', visible: false, enabled: true)
      create(:agent, name: 'Disabled Agent', visible: true, enabled: false)
    end

    it 'returns only visible and enabled agents' do
      available = executor.send(:available_agents)
      expect(available).to include('Agent 1')
      expect(available).to include('Agent 2')
      expect(available).not_to include('Hidden Agent')
      expect(available).not_to include('Disabled Agent')
    end
  end
end