# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProviderConfig, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:adapter_type) }
    
    it 'validates uniqueness of name' do
      create(:provider_config, name: "OpenAI")
      expect(build(:provider_config, name: "OpenAI")).not_to be_valid
    end

    it 'validates inclusion of adapter_type' do
      expect(build(:provider_config, adapter_type: "openai")).to be_valid
      expect(build(:provider_config, adapter_type: "anthropic")).to be_valid
      expect(build(:provider_config, adapter_type: "ollama")).to be_valid
      expect(build(:provider_config, adapter_type: "invalid")).not_to be_valid
    end
  end

  describe 'scopes' do
    let!(:enabled_provider) { create(:provider_config, :openai, enabled: true) }
    let!(:disabled_provider) { create(:provider_config, :anthropic, enabled: false) }

    describe '.enabled_providers' do
      it 'returns only enabled providers' do
        expect(ProviderConfig.enabled_providers).to include(enabled_provider)
        expect(ProviderConfig.enabled_providers).not_to include(disabled_provider)
      end
    end
  end

  describe '#api_key' do
    let(:agent) { create(:agent) }
    let(:provider) { create(:provider_config, :openai, vault_key: "providers/openai_api_key") }

    context 'when vault_key is present' do
      context 'and vault entry exists' do
        let!(:vault_entry) { create(:vault_entry, namespace: "providers", key: "openai_api_key", encrypted_value: "sk-test123", agent: nil) }

        it 'returns the decrypted value' do
          expect(provider.api_key).to eq("sk-test123")
        end

        it 'resolves agent-scoped vault entry if agent provided' do
          agent_entry = create(:vault_entry, namespace: "providers", key: "openai_api_key", encrypted_value: "sk-agent123", agent: agent)
          expect(provider.api_key(agent: agent)).to eq("sk-agent123")
        end
      end

      context 'and vault entry does not exist' do
        it 'returns nil' do
          expect(provider.api_key).to be_nil
        end
      end
    end

    context 'when vault_key is blank' do
      let(:provider) { create(:provider_config, :ollama, vault_key: nil) }

      it 'returns nil' do
        expect(provider.api_key).to be_nil
      end
    end
  end

  describe 'default values' do
    let(:provider) { ProviderConfig.new(name: "Test", adapter_type: "openai") }

    it 'initializes model_definitions as empty array' do
      expect(provider.model_definitions).to eq([])
    end

    it 'initializes enabled to true' do
      expect(provider.enabled).to be true
    end
  end

  describe 'factory' do
    it 'creates a valid provider config' do
      expect(build(:provider_config)).to be_valid
    end

    it 'creates valid providers with traits' do
      expect(build(:provider_config, :openai)).to be_valid
      expect(build(:provider_config, :anthropic)).to be_valid
      expect(build(:provider_config, :ollama)).to be_valid
      expect(build(:provider_config, :disabled)).to be_valid
    end
  end
end
