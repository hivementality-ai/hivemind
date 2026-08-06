# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Vault entries", type: :request do
  describe "as an owner" do
    let(:user) { create(:user, :owner) }
    before { sign_in user }

    it "lists keys with redacted values, never the plaintext" do
      VaultEntry.create!(namespace: "openai", key: "api_key", encrypted_value: "sk-proj-supersecret1234")
      get vault_entries_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("openai.api_key")
      expect(response.body).not_to include("sk-proj-supersecret1234")
      expect(response.body).to include(Vault::Redactor.redact("sk-proj-supersecret1234"))
    end

    it "creates a global (agent-less) key" do
      post vault_entries_path, params: {
        vault_entry: { namespace: "github", key: "token", value: "ghp_abc123def456", purpose: "CI pushes" }
      }

      expect(response).to redirect_to(vault_entries_path)
      entry = VaultEntry.find_by(namespace: "github", key: "token")
      expect(entry).to be_present
      expect(entry.agent_id).to be_nil
      expect(entry.value).to eq("ghp_abc123def456")
      expect(entry.metadata["purpose"]).to eq("CI pushes")
    end

    it "re-renders on invalid input" do
      post vault_entries_path, params: { vault_entry: { namespace: "", key: "", value: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "deletes a key" do
      entry = VaultEntry.create!(namespace: "stripe", key: "sk", encrypted_value: "secret")
      expect { delete vault_entry_path(entry) }.to change(VaultEntry, :count).by(-1)
      expect(response).to redirect_to(vault_entries_path)
    end
  end

  describe "as a viewer" do
    before { sign_in create(:user, :viewer) }

    it "is denied access" do
      get vault_entries_path
      expect(response).to redirect_to(root_path)
    end
  end
end
