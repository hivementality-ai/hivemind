# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditLog, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:actor_type) }
    it { should validate_presence_of(:actor_id) }
    it { should validate_presence_of(:action) }
  end

  describe 'scopes' do
    let!(:recent_log) { create(:audit_log, created_at: 1.hour.ago) }
    let!(:old_log) { create(:audit_log, created_at: 1.week.ago) }
    let!(:agent_log) { create(:audit_log, actor_type: "agent", actor_id: "1", action: "vault.read") }
    let!(:user_log) { create(:audit_log, :user_actor, actor_id: "2", action: "vault.write") }
    let!(:read_action_log) { create(:audit_log, action: "vault.read") }
    let!(:write_action_log) { create(:audit_log, action: "vault.write") }

    describe '.recent' do
      it 'returns logs ordered by created_at desc' do
        logs = AuditLog.recent
        expect(logs.first.created_at).to be > logs.last.created_at
      end
    end

    describe '.by_actor' do
      it 'returns logs for specific actor' do
        logs = AuditLog.by_actor("agent", "1")
        expect(logs).to include(agent_log)
        expect(logs).not_to include(user_log)
      end
    end

    describe '.by_action' do
      it 'returns logs for specific action' do
        logs = AuditLog.by_action("vault.read")
        expect(logs).to include(read_action_log)
        expect(logs).not_to include(write_action_log)
      end
    end
  end

  describe '#readonly?' do
    context 'when persisted' do
      it 'returns true for append-only enforcement' do
        log = create(:audit_log)
        expect(log.readonly?).to be true
      end
    end

    context 'when not persisted' do
      it 'returns false to allow creation' do
        log = build(:audit_log)
        expect(log.readonly?).to be false
      end
    end
  end

  describe '.record' do
    it 'creates audit log with required attributes' do
      expect {
        AuditLog.record(
          actor_type: "agent",
          actor_id: 123,
          action: "vault.read",
          resource: "vault_entries/1",
          metadata: { key: "value" }
        )
      }.to change(AuditLog, :count).by(1)

      log = AuditLog.last
      expect(log.actor_type).to eq("agent")
      expect(log.actor_id).to eq("123")
      expect(log.action).to eq("vault.read")
      expect(log.resource).to eq("vault_entries/1")
      expect(log.metadata).to eq({ "key" => "value" })
    end

    it 'converts actor_id to string' do
      AuditLog.record(actor_type: "user", actor_id: 456, action: "test")
      log = AuditLog.last
      expect(log.actor_id).to eq("456")
    end

    it 'handles nil resource' do
      AuditLog.record(actor_type: "system", actor_id: "system", action: "startup")
      log = AuditLog.last
      expect(log.resource).to be_nil
    end

    it 'handles empty metadata' do
      AuditLog.record(actor_type: "system", actor_id: "system", action: "test", metadata: {})
      log = AuditLog.last
      expect(log.metadata).to eq({})
    end
  end

  describe 'immutability' do
    let(:log) { create(:audit_log) }

    it 'prevents updates' do
      expect { log.update!(action: "new_action") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it 'prevents deletion' do
      expect { log.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe 'factory' do
    it 'creates a valid audit log' do
      expect(build(:audit_log)).to be_valid
    end

    it 'creates valid logs with traits' do
      expect(build(:audit_log, :vault_read)).to be_valid
      expect(build(:audit_log, :vault_write)).to be_valid
      expect(build(:audit_log, :system_actor)).to be_valid
      expect(build(:audit_log, :user_actor)).to be_valid
    end
  end
end
