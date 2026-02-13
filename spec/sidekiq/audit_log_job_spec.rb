# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditLogJob, type: :job do
  describe '#perform' do
    let(:actor_type) { "agent" }
    let(:actor_id) { "123" }
    let(:action) { "vault.read" }
    let(:resource) { "vault_entries/1" }
    let(:metadata) { { "key" => "value" } }

    it 'creates an AuditLog record' do
      expect {
        described_class.new.perform(actor_type, actor_id, action, resource, metadata)
      }.to change(AuditLog, :count).by(1)

      log = AuditLog.last
      expect(log.actor_type).to eq(actor_type)
      expect(log.actor_id).to eq(actor_id)
      expect(log.action).to eq(action)
      expect(log.resource).to eq(resource)
      expect(log.metadata).to eq(metadata)
    end

    it 'handles nil resource' do
      expect {
        described_class.new.perform(actor_type, actor_id, action, nil, metadata)
      }.to change(AuditLog, :count).by(1)

      log = AuditLog.last
      expect(log.resource).to be_nil
    end

    it 'handles nil metadata' do
      expect {
        described_class.new.perform(actor_type, actor_id, action, resource, nil)
      }.to change(AuditLog, :count).by(1)

      log = AuditLog.last
      expect(log.metadata).to eq({})
    end

    it 'handles empty metadata' do
      expect {
        described_class.new.perform(actor_type, actor_id, action, resource, {})
      }.to change(AuditLog, :count).by(1)

      log = AuditLog.last
      expect(log.metadata).to eq({})
    end
  end

  describe 'sidekiq options' do
    it 'uses low priority queue' do
      expect(described_class.sidekiq_options_hash['queue']).to eq('low')
    end

    it 'retries 3 times' do
      expect(described_class.sidekiq_options_hash['retry']).to eq(3)
    end
  end
end
