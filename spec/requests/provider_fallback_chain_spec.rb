# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Backup brain settings", type: :request do
  let!(:claude) { create(:provider_config, :anthropic) }
  let!(:local) { create(:provider_config, :ollama) }
  let(:key) { Providers::DefaultFallback::SETTING_KEY }

  before { sign_in create(:user, :owner) }

  describe "GET /providers" do
    it "explains the backup brain in plain words" do
      get providers_path
      expect(response.body).to include("If your main brain fails, Hivemind tries these next, in order.")
    end

    it "lists the saved chain first, in order, checked" do
      Setting.set(key, [ { provider_config_id: local.id } ].to_json)
      get providers_path
      form = response.body[/<form[^>]*fallback_chain.*?<\/form>/m]
      expect(form.index("Ollama")).to be < form.index("Anthropic")
      expect(form).to match(/value="#{local.id}" checked/)
    end
  end

  describe "PATCH /providers/fallback_chain" do
    it "saves the chosen providers in the shape DefaultFallback reads" do
      patch fallback_chain_providers_path,
            params: { chain_ids: [ local.id, claude.id ], models: { local.id => "llama2", claude.id => "" } }

      expect(response).to redirect_to(providers_path)
      expect(JSON.parse(Setting.get(key))).to eq(
        [ { "provider_config_id" => local.id, "model" => "llama2" }, { "provider_config_id" => claude.id } ]
      )
      expect(Providers::DefaultFallback.entries.map { |e| e["provider_config_id"] }).to eq([ local.id, claude.id ])
    end

    it "rejects a disabled provider and leaves the saved chain alone" do
      off = create(:provider_config, :openai, enabled: false)
      Setting.set(key, [ { provider_config_id: claude.id } ].to_json)

      patch fallback_chain_providers_path, params: { chain_ids: [ off.id ] }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("existing, enabled provider")
      expect(JSON.parse(Setting.get(key))).to eq([ { "provider_config_id" => claude.id } ])
    end

    it "rejects a provider that does not exist" do
      patch fallback_chain_providers_path, params: { chain_ids: [ 0 ] }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Setting.get(key)).to be_nil
    end

    it "rejects a model the provider does not offer" do
      patch fallback_chain_providers_path, params: { chain_ids: [ claude.id ], models: { claude.id => "nope" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Setting.get(key)).to be_nil
    end

    it "clears the chain when nothing is checked" do
      Setting.set(key, [ { provider_config_id: claude.id } ].to_json)
      patch fallback_chain_providers_path
      expect(JSON.parse(Setting.get(key))).to eq([])
    end
  end
end
