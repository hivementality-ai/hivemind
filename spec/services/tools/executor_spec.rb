# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::Executor, type: :service do
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent) }

  describe '.call' do
    let(:tool) { create(:tool, executor_type: 'shell') }
    let(:input) { { command: 'echo "hello"' } }

    context 'with known executor type' do
      it 'creates a ToolExecution record' do
        expect {
          Tools::Executor.call(tool: tool, input: input, agent: agent, session: session)
        }.to change(ToolExecution, :count).by(1)
      end

      it 'returns success when executor succeeds' do
        allow_any_instance_of(Tools::ShellExecutor).to receive(:call)
          .and_return(ServiceResponse.success(data: { output: 'hello', exit_code: 0 }))

        result = Tools::Executor.call(tool: tool, input: input, agent: agent, session: session)
        expect(result).to be_success
      end

      it 'returns failure when executor fails' do
        allow_any_instance_of(Tools::ShellExecutor).to receive(:call)
          .and_return(ServiceResponse.failure(error: 'Command failed'))

        result = Tools::Executor.call(tool: tool, input: input, agent: agent, session: session)
        expect(result).to be_failure
      end
    end

    context 'with unknown executor type' do
      let(:unknown_tool) { create(:tool, executor_type: 'shell') }

      before do
        allow_any_instance_of(Tools::Executor).to receive(:initialize).and_call_original
        allow(Tools::Executor::EXECUTORS).to receive(:[]).and_return(nil)
      end

      it 'returns failure' do
        result = Tools::Executor.call(tool: unknown_tool, input: input, agent: agent, session: session)
        expect(result).to be_failure
        expect(result.error).to include('Unknown executor')
      end
    end
  end

  describe 'execution recording' do
    let(:tool) { create(:tool, executor_type: 'shell') }
    let(:input) { { command: 'ls' } }

    before do
      allow_any_instance_of(Tools::ShellExecutor).to receive(:call)
        .and_return(ServiceResponse.success(data: { output: 'file.txt', exit_code: 0 }))
    end

    it 'marks execution as completed on success' do
      Tools::Executor.call(tool: tool, input: input, agent: agent, session: session)
      execution = ToolExecution.last
      expect(execution.status).to eq('completed')
      expect(execution.output).to eq('file.txt')
      expect(execution.exit_code).to eq(0)
    end

    it 'records duration' do
      Tools::Executor.call(tool: tool, input: input, agent: agent, session: session)
      execution = ToolExecution.last
      expect(execution.duration_ms).to be_present
      expect(execution.duration_ms).to be > 0
    end
  end

  describe 'error handling' do
    let(:tool) { create(:tool, executor_type: 'shell') }
    let(:input) { {} }

    before do
      allow_any_instance_of(Tools::ShellExecutor).to receive(:call)
        .and_raise(StandardError.new('Unexpected error'))
    end

    it 'catches and records exceptions' do
      result = Tools::Executor.call(tool: tool, input: input, agent: agent, session: session)
      expect(result).to be_failure
      execution = ToolExecution.last
      expect(execution.status).to eq('failed')
      expect(execution.error).to include('Unexpected error')
    end
  end
end
