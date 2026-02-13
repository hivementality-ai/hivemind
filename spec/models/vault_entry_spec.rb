# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VaultEntry, type: :model do
  describe 'associations' do
    it { should belong_to(:agent).optional }
  end

  describe 'validations' do
    it { should validate_presence_of(:namespace) }
    it { should validate_presence_of(:key) }

    describe 'uniqueness validation' do
      let(:agent) { create(:agent) }

      it 'validates uniqueness of key scoped to agent_id and namespace' do
        create(:vault_entry, agent: agent, namespace: "secrets", key: "api_key")
        duplicate = build(:vault_entry, agent: agent, namespace: "secrets", key: "api_key")
        expect(duplicate).not_to be_valid
      end

      it 'allows same key in different namespaces' do
        create(:vault_entry, agent: agent, namespace: "secrets", key: "api_key")
        different_namespace = build(:vault_entry, agent: agent, namespace: "config", key: "api_key")
        expect(different_namespace).to be_valid
      end

      it 'allows same key for different agents' do
        create(:vault_entry, agent: agent, namespace: "secrets", key: "api_key")
        different_agent = build(:vault_entry, agent: create(:agent), namespace: "secrets", key: "api_key")
        expect(different_agent).to be_valid
      end

      it 'allows same key for agent-scoped and global' do
        create(:vault_entry, agent: agent, namespace: "secrets", key: "api_key")
        global = build(:vault_entry, agent: nil, namespace: "secrets", key: "api_key")
        expect(global).to be_valid
      end
    end
  end

  describe 'encryption' do
    it 'encrypts the encrypted_value attribute' do
      entry = create(:vault_entry, encrypted_value: "secret123")
      # The actual encryption is handled by Rails, just verify it's stored
      expect(entry.reload.encrypted_value).to eq("secret123")
    end
  end

  describe 'scopes' do
    let(:agent) { create(:agent) }
    let!(:global_entry) { create(:vault_entry, :global, namespace: "config", key: "global_key") }
    let!(:agent_entry) { create(:vault_entry, agent: agent, namespace: "config", key: "agent_key") }
    let!(:other_namespace) { create(:vault_entry, agent: agent, namespace: "other", key: "other_key") }

    describe '.global' do
      it 'returns only global entries' do
        expect(VaultEntry.global).to include(global_entry)
        expect(VaultEntry.global).not_to include(agent_entry)
      end
    end

    describe '.for_agent' do
      it 'returns entries for specific agent and global' do
        entries = VaultEntry.for_agent(agent)
        expect(entries).to include(agent_entry, global_entry)
      end
    end

    describe '.in_namespace' do
      it 'returns entries in the specified namespace' do
        entries = VaultEntry.in_namespace("config")
        expect(entries).to include(global_entry, agent_entry)
        expect(entries).not_to include(other_namespace)
      end
    end
  end

  describe '.resolve' do
    let(:agent) { create(:agent) }

    context 'when agent-scoped entry exists' do
      let!(:agent_entry) { create(:vault_entry, agent: agent, namespace: "secrets", key: "api_key", encrypted_value: "agent_secret") }

      it 'returns the agent-scoped entry' do
        result = VaultEntry.resolve(namespace: "secrets", key: "api_key", agent: agent)
        expect(result).to eq(agent_entry)
      end
    end

    context 'when only global entry exists' do
      let!(:global_entry) { create(:vault_entry, :global, namespace: "secrets", key: "api_key", encrypted_value: "global_secret") }

      it 'returns the global entry' do
        result = VaultEntry.resolve(namespace: "secrets", key: "api_key", agent: agent)
        expect(result).to eq(global_entry)
      end
    end

    context 'when both agent-scoped and global entries exist' do
      let!(:agent_entry) { create(:vault_entry, agent: agent, namespace: "secrets", key: "api_key", encrypted_value: "agent_secret") }
      let!(:global_entry) { create(:vault_entry, :global, namespace: "secrets", key: "api_key", encrypted_value: "global_secret") }

      it 'prioritizes agent-scoped over global' do
        result = VaultEntry.resolve(namespace: "secrets", key: "api_key", agent: agent)
        expect(result).to eq(agent_entry)
        expect(result.encrypted_value).to eq("agent_secret")
      end
    end

    context 'when no entry exists' do
      it 'returns nil' do
        result = VaultEntry.resolve(namespace: "nonexistent", key: "missing", agent: agent)
        expect(result).to be_nil
      end
    end

    context 'when agent is nil' do
      let!(:global_entry) { create(:vault_entry, :global, namespace: "secrets", key: "api_key") }

      it 'returns only global entries' do
        result = VaultEntry.resolve(namespace: "secrets", key: "api_key", agent: nil)
        expect(result).to eq(global_entry)
      end
    end
  end

  describe 'factory' do
    it 'creates a valid vault entry' do
      expect(build(:vault_entry)).to be_valid
    end

    it 'creates valid entries with traits' do
      expect(build(:vault_entry, :global)).to be_valid
      expect(build(:vault_entry, :agent_scoped)).to be_valid
      expect(build(:vault_entry, :openai_key)).to be_valid
      expect(build(:vault_entry, :anthropic_key)).to be_valid
    end
  end
end
