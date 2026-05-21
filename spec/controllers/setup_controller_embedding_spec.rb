# frozen_string_literal: true

require "rails_helper"

RSpec.describe SetupController, "embedding provider selection", type: :controller do
  let(:user) { create(:user, :owner) }

  before do
    sign_in user
    # Ensure setup is not complete so we can access the wizard
    allow(Setting).to receive(:get).and_call_original
    allow(Setting).to receive(:get).with("setup_complete").and_return(nil)
  end

  describe "POST #save_provider" do
    let(:valid_params) do
      {
        providers: {
          anthropic: { api_key: "sk-ant-test", models: [ "claude-sonnet-4-5" ], default_model: "claude-sonnet-4-5" }
        },
        embedding_provider: "ollama"
      }
    end

    it "saves the embedding provider setting" do
      post :save_provider, params: valid_params

      expect(Setting.get("memory_embeddings_provider")).to eq("ollama")
    end

    it "saves gemini as embedding provider" do
      params = valid_params.merge(embedding_provider: "gemini", gemini_embedding_api_key: "AIzaTestKey123")
      post :save_provider, params: params

      expect(Setting.get("memory_embeddings_provider")).to eq("gemini")
    end

    it "stores gemini embedding API key in vault" do
      params = valid_params.merge(embedding_provider: "gemini", gemini_embedding_api_key: "AIzaTestKey123")
      post :save_provider, params: params

      vault_entry = VaultEntry.find_by(namespace: "embedding", key: "google_ai_api_key")
      expect(vault_entry).to be_present
    end

    it "defaults to ollama when no embedding provider specified" do
      params = valid_params.except(:embedding_provider)
      post :save_provider, params: params

      expect(Setting.get("memory_embeddings_provider")).to eq("ollama")
    end

    it "ignores invalid embedding provider values" do
      params = valid_params.merge(embedding_provider: "invalid_provider")
      post :save_provider, params: params

      expect(Setting.get("memory_embeddings_provider")).to be_nil
    end

    context "when ollama embedding is selected with a custom base_url" do
      let(:remote_url) { "http://192.168.1.100:11434" }
      let(:params_with_remote_url) do
        valid_params.merge(
          embedding_provider: "ollama",
          providers: {
            anthropic: { api_key: "sk-ant-test", models: [ "claude-sonnet-4-5" ], default_model: "claude-sonnet-4-5" },
            ollama: { base_url: remote_url }
          }
        )
      end

      it "creates a ProviderConfig for ollama with the custom base_url" do
        post :save_provider, params: params_with_remote_url

        pc = ProviderConfig.find_by(adapter_type: "ollama")
        expect(pc).to be_present
        expect(pc.base_url).to eq(remote_url)
      end

      it "sets enabled: true on the ProviderConfig so OllamaAdapter can find it" do
        post :save_provider, params: params_with_remote_url

        pc = ProviderConfig.find_by(adapter_type: "ollama")
        expect(pc.enabled).to be(true)
      end

      it "re-enables a previously disabled ProviderConfig and updates base_url" do
        existing = create(:provider_config, adapter_type: "ollama", name: "ollama",
                          vault_key: "providers/ollama_api_key", enabled: false)

        post :save_provider, params: params_with_remote_url

        expect(existing.reload.enabled).to be(true)
        expect(existing.reload.base_url).to eq(remote_url)
      end
    end

    context "when ollama embedding is selected without a custom base_url" do
      it "does not create a ProviderConfig for ollama" do
        post :save_provider, params: valid_params

        expect(ProviderConfig.find_by(adapter_type: "ollama")).to be_nil
      end
    end
  end
end
