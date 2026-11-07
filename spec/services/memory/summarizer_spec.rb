# frozen_string_literal: true

require "rails_helper"

RSpec.describe Memory::Summarizer do
  subject(:summarizer) { described_class.new(agent: agent) }

  let(:agent) { create(:agent) }
  let(:ollama_adapter) { instance_double("Providers::OllamaAdapter") }
  let(:claude_adapter) { instance_double("Providers::AnthropicAdapter") }
  let(:ollama) do
    create(:provider_config, name: "studio", adapter_type: "ollama", model_definitions: [ { "id" => "qwen3:8b" } ])
  end

  before do
    create(:provider_config, name: "claude", adapter_type: "anthropic")
    allow(Providers::Resolver).to receive(:call).with(hash_including(provider_name: "ollama"))
      .and_return(ServiceResponse.success(data: { adapter: ollama_adapter }))
    allow(Providers::Resolver).to receive(:call).with(hash_including(provider_name: "anthropic"))
      .and_return(ServiceResponse.success(data: { adapter: claude_adapter }))
  end

  describe "#resolve_cheap_provider" do
    it "prefers a healthy local Ollama with its configured model" do
      allow(Agents::ModelRouter).to receive(:local_provider).and_return(config: ollama, model: "qwen3:8b")

      expect(summarizer.send(:resolve_cheap_provider)).to eq([ ollama_adapter, "qwen3:8b" ])
    end

    it "keeps the Anthropic choice when no local provider is available" do
      allow(Agents::ModelRouter).to receive(:local_provider).and_return(nil)

      expect(summarizer.send(:resolve_cheap_provider))
        .to eq([ claude_adapter, LlmModelRegistry::Anthropic::DEFAULT_SUMMARIZER ])
    end

    it "uses the configured Ollama model, not a hardcoded one, as the last resort" do
      ollama
      ProviderConfig.where(adapter_type: "anthropic").delete_all
      allow(Agents::ModelRouter).to receive(:local_provider).and_return(nil)

      expect(summarizer.send(:resolve_cheap_provider)).to eq([ ollama_adapter, "qwen3:8b" ])
    end
  end
end
