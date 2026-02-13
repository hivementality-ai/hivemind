# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vault::Read do
  describe '.call' do
    let(:agent) { create(:agent) }
    let(:namespace) { "secrets" }
    let(:key) { "api_key" }

    context 'when entry exists' do
      let!(:vault_entry) { create(:vault_entry, namespace: namespace, key: key, encrypted_value: "secret123", agent: nil) }

      it 'returns success with the value' do
        result = described_class.call(namespace: namespace, key: key)

        expect(result.success?).to be true
        expect(result.data[:value]).to eq("secret123")
      end

      it 'creates an audit log entry' do
        expect {
          described_class.call(namespace: namespace, key: key)
        }.to change { Sidekiq::Job.jobs.size }.by(1)

        job = Sidekiq::Job.jobs.last
        expect(job['class']).to eq('AuditLogJob')
        expect(job['args'][2]).to eq('vault.read')
      end

      context 'with agent context' do
        let!(:agent_entry) { create(:vault_entry, namespace: namespace, key: key, encrypted_value: "agent_secret", agent: agent) }

        it 'resolves agent-scoped entry over global' do
          result = described_class.call(namespace: namespace, key: key, agent: agent)

          expect(result.success?).to be true
          expect(result.data[:value]).to eq("agent_secret")
        end

        it 'logs the read with agent actor' do
          described_class.call(namespace: namespace, key: key, agent: agent)

          job = Sidekiq::Job.jobs.last
          expect(job['args'][0]).to eq('agent')
          expect(job['args'][1]).to eq(agent.id.to_s)
        end
      end
    end

    context 'when entry does not exist' do
      it 'returns failure with error message' do
        result = described_class.call(namespace: namespace, key: key)

        expect(result.success?).to be false
        expect(result.error).to eq("Secret not found: #{namespace}/#{key}")
      end

      it 'does not create an audit log' do
        expect {
          described_class.call(namespace: namespace, key: key)
        }.not_to change { Sidekiq::Job.jobs.size }
      end
    end
  end
end
