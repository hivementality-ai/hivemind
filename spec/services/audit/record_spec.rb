# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Audit::Record do
  describe '.call' do
    let(:actor_type) { "agent" }
    let(:actor_id) { 123 }
    let(:action) { "vault.read" }
    let(:resource) { "vault_entries/1" }
    let(:metadata) { { key: "value" } }

    it 'enqueues AuditLogJob with correct arguments' do
      expect {
        described_class.call(
          actor_type: actor_type,
          actor_id: actor_id,
          action: action,
          resource: resource,
          metadata: metadata
        )
      }.to change { Sidekiq::Job.jobs.size }.by(1)

      job = Sidekiq::Job.jobs.last
      expect(job['class']).to eq('AuditLogJob')
      expect(job['args']).to eq([
        actor_type,
        actor_id.to_s,
        action,
        resource,
        { "key" => "value" }
      ])
    end

    it 'returns success' do
      result = described_class.call(
        actor_type: actor_type,
        actor_id: actor_id,
        action: action
      )

      expect(result).to be_a(ServiceResponse)
      expect(result.success?).to be true
    end

    it 'handles nil resource' do
      expect {
        described_class.call(
          actor_type: actor_type,
          actor_id: actor_id,
          action: action,
          resource: nil
        )
      }.to change { Sidekiq::Job.jobs.size }.by(1)

      job = Sidekiq::Job.jobs.last
      expect(job['args'][3]).to be_nil
    end

    it 'handles empty metadata' do
      expect {
        described_class.call(
          actor_type: actor_type,
          actor_id: actor_id,
          action: action,
          metadata: {}
        )
      }.to change { Sidekiq::Job.jobs.size }.by(1)

      job = Sidekiq::Job.jobs.last
      expect(job['args'][4]).to eq({})
    end

    it 'converts actor_id to string' do
      described_class.call(
        actor_type: actor_type,
        actor_id: actor_id,
        action: action
      )

      job = Sidekiq::Job.jobs.last
      expect(job['args'][1]).to eq("123")
    end

    it 'serializes metadata as JSON' do
      described_class.call(
        actor_type: actor_type,
        actor_id: actor_id,
        action: action,
        metadata: { nested: { key: "value" } }
      )

      job = Sidekiq::Job.jobs.last
      expect(job['args'][4]).to eq({ "nested" => { "key" => "value" } })
    end
  end
end
