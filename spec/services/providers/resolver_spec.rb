# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Providers::Resolver do
  describe '.call' do
    let(:agent) { create(:agent) }
    let(:provider_name) { "OpenAI" }

    context 'when provider exists and is enabled' do
      let!(:provider_config) { create(:provider_config, :openai, name: provider_name) }
      let!(:vault_entry) do
        create(:vault_entry, namespace: "providers", key: "openai_api_key", encrypted_value: "sk-test123", agent: nil)
      end

      it 'returns success with adapter' do
        result = described_class.call(provider_name: provider_name)

        expect(result.success?).to be true
        expect(result.data[:adapter]).to be_a(Providers::OpenaiAdapter)
      end

      it 'resolves API key from vault' do
        result = described_class.call(provider_name: provider_name)

        adapter = result.data[:adapter]
        expect(adapter.instance_variable_get(:@api_key)).to eq("sk-test123")
      end

      context 'with agent context' do
        let!(:agent_vault_entry) do
          create(:vault_entry, namespace: "providers", key: "openai_api_key", encrypted_value: "sk-agent123", agent: agent)
        end

        it 'resolves agent-scoped API key' do
          result = described_class.call(provider_name: provider_name, agent: agent)

          adapter = result.data[:adapter]
          expect(adapter.instance_variable_get(:@api_key)).to eq("sk-agent123")
        end
      end
    end

    context 'when provider is disabled' do
      let!(:provider_config) { create(:provider_config, :openai, :disabled, name: provider_name) }

      it 'returns failure with not found error' do
        result = described_class.call(provider_name: provider_name)

        expect(result.success?).to be false
        expect(result.error).to eq("Provider not found: #{provider_name}")
      end
    end

    context 'when provider does not exist' do
      it 'returns failure with not found error' do
        result = described_class.call(provider_name: "NonExistent")

        expect(result.success?).to be false
        expect(result.error).to eq("Provider not found: NonExistent")
      end
    end

    context 'with different adapter types' do
      it 'returns OpenaiAdapter for openai type' do
        provider = create(:provider_config, :openai, name: "OpenAI")
        result = described_class.call(provider_name: "OpenAI")

        expect(result.success?).to be true
        expect(result.data[:adapter]).to be_a(Providers::OpenaiAdapter)
      end

      it 'returns AnthropicAdapter for anthropic type' do
        provider = create(:provider_config, :anthropic, name: "Anthropic")
        result = described_class.call(provider_name: "Anthropic")

        expect(result.success?).to be true
        expect(result.data[:adapter]).to be_a(Providers::AnthropicAdapter)
      end

      it 'returns OllamaAdapter for ollama type' do
        provider = create(:provider_config, :ollama, name: "Ollama")
        result = described_class.call(provider_name: "Ollama")

        expect(result.success?).to be true
        expect(result.data[:adapter]).to be_a(Providers::OllamaAdapter)
      end
    end

    context 'when adapter type is unknown' do
      let!(:provider_config) do
        create(:provider_config, name: provider_name, adapter_type: "openai")
      end

      before do
        # Stub ADAPTERS constant to simulate unknown adapter
        stub_const("Providers::Resolver::ADAPTERS", {})
      end

      it 'returns failure with unknown adapter error' do
        result = described_class.call(provider_name: provider_name)

        expect(result.success?).to be false
        expect(result.error).to eq("Unknown adapter: openai")
      end
    end
  end
end
