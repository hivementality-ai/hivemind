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
  end
end
