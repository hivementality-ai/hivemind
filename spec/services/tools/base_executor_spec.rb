# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::BaseExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: config, agent: agent) }
  let(:input) { { test: 'data' } }
  let(:config) { { timeout: 30 } }
  let(:agent) { create(:agent) }

  describe '#initialize' do
    it 'sets input, config, and agent' do
      expect(executor.instance_variable_get(:@input)).to eq(input)
      expect(executor.instance_variable_get(:@config)).to eq(config)
      expect(executor.instance_variable_get(:@agent)).to eq(agent)
    end

    it 'works with nil agent' do
      executor_without_agent = described_class.new(input: input, config: config, agent: nil)
      expect(executor_without_agent.instance_variable_get(:@agent)).to be_nil
    end

    it 'works with empty config' do
      executor_with_empty_config = described_class.new(input: input, config: {}, agent: agent)
      expect(executor_with_empty_config.instance_variable_get(:@config)).to eq({})
    end
  end

  describe '#call' do
    it 'raises NotImplementedError' do
      expect { executor.call }.to raise_error(NotImplementedError, "#{described_class}#call must be implemented")
    end
  end

  describe 'private methods' do
    it 'provides access to input via private method' do
      expect(executor.send(:input)).to eq(input)
    end

    it 'provides access to config via private method' do
      expect(executor.send(:config)).to eq(config)
    end

    it 'provides access to agent via private method' do
      expect(executor.send(:agent)).to eq(agent)
    end
  end
end