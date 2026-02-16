# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vault::Write do
  describe '.call' do
    let(:agent) { create(:agent) }
    let(:namespace) { "secrets" }
    let(:key) { "api_key" }
    let(:value) { "secret123" }
    let(:metadata) { { source: "test" } }

    context 'when creating a new entry' do
      it 'creates a vault entry' do
        expect {
          described_class.call(namespace: namespace, key: key, value: value)
        }.to change(VaultEntry, :count).by(1)

        entry = VaultEntry.last
        expect(entry.namespace).to eq(namespace)
        expect(entry.key).to eq(key)
        expect(entry.encrypted_value).to eq(value)
      end

      it 'returns success with the entry' do
        result = described_class.call(namespace: namespace, key: key, value: value)

        expect(result.success?).to be true
        expect(result.data[:entry]).to be_a(VaultEntry)
      end

      it 'creates an audit log for vault.create' do
        described_class.call(namespace: namespace, key: key, value: value)

        job = Sidekiq::Job.jobs.last
        expect(job['class']).to eq('AuditLogJob')
        expect(job['args'][2]).to eq('vault.create')
      end

      it 'stores metadata' do
        described_class.call(namespace: namespace, key: key, value: value, metadata: metadata)

        entry = VaultEntry.last
        expect(entry.metadata).to include("source" => "test")
      end

      context 'with agent context' do
        it 'creates agent-scoped entry' do
          result = described_class.call(namespace: namespace, key: key, value: value, agent: agent)

          entry = result.data[:entry]
          expect(entry.agent_id).to eq(agent.id)
        end

        it 'logs with agent actor' do
          described_class.call(namespace: namespace, key: key, value: value, agent: agent)

          job = Sidekiq::Job.jobs.last
          expect(job['args'][0]).to eq('agent')
          expect(job['args'][1]).to eq(agent.id.to_s)
        end
      end
    end

    context 'when updating an existing entry' do
      let!(:existing_entry) do
        create(:vault_entry,
               namespace: namespace,
               key: key,
               encrypted_value: "old_value",
               metadata: { old: "data" },
               agent: nil)
      end

      it 'does not create a new entry' do
        expect {
          described_class.call(namespace: namespace, key: key, value: value)
        }.not_to change(VaultEntry, :count)
      end

      it 'updates the encrypted_value' do
        described_class.call(namespace: namespace, key: key, value: value)

        existing_entry.reload
        expect(existing_entry.encrypted_value).to eq(value)
      end

      it 'merges metadata' do
        described_class.call(namespace: namespace, key: key, value: value, metadata: metadata)

        existing_entry.reload
        expect(existing_entry.metadata).to include("old" => "data", "source" => "test")
      end

      it 'creates an audit log for vault.update' do
        described_class.call(namespace: namespace, key: key, value: value)

        job = Sidekiq::Job.jobs.last
        expect(job['args'][2]).to eq('vault.update')
      end

      it 'returns success' do
        result = described_class.call(namespace: namespace, key: key, value: value)

        expect(result.success?).to be true
      end
    end

    context 'when save fails' do
      before do
        allow_any_instance_of(VaultEntry).to receive(:save).and_return(false)
        allow_any_instance_of(VaultEntry).to receive(:errors).and_return(
          double(full_messages: [ "Validation failed" ])
        )
      end

      it 'returns failure with error messages' do
        result = described_class.call(namespace: namespace, key: key, value: value)

        expect(result.success?).to be false
        expect(result.error).to eq([ "Validation failed" ])
      end

      it 'does not create an audit log' do
        expect {
          described_class.call(namespace: namespace, key: key, value: value)
        }.not_to change { Sidekiq::Job.jobs.size }
      end
    end
  end
end
