# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Vault entries", type: :request do
  let(:secret) { "sk-proj-supersecret1234" }

  describe "as an owner" do
    before { sign_in create(:user, :owner) }

    it "lists entries by namespace and key with set status and never the value" do
      VaultEntry.create!(namespace: "openai", key: "api_key", encrypted_value: secret)

      get vault_entries_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("openai", "api_key", ">set<", "updated")
      expect(response.body).not_to include(secret)
    end

    it "renders the new and replace forms without the value" do
      entry = VaultEntry.create!(namespace: "openai", key: "api_key", encrypted_value: secret)

      get new_vault_entry_path
      expect(response).to have_http_status(:ok)
      get edit_vault_entry_path(entry)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(secret)
    end

    it "creates a global entry" do
      post vault_entries_path, params: { vault_entry: { namespace: "github", key: "token", value: "ghp_abc123def456" } }

      expect(response).to redirect_to(vault_entries_path)
      entry = VaultEntry.find_by(namespace: "github", key: "token")
      expect(entry).to have_attributes(agent_id: nil, value: "ghp_abc123def456")
    end

    it "refuses to create over an existing key and keeps the old value" do
      VaultEntry.create!(namespace: "github", key: "token", encrypted_value: "old-value-1")

      post vault_entries_path, params: { vault_entry: { namespace: "github", key: "token", value: "new-value-2" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(VaultEntry.find_by(namespace: "github", key: "token").value).to eq("old-value-1")
    end

    it "re-renders on a blank value" do
      post vault_entries_path, params: { vault_entry: { namespace: "github", key: "token", value: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(VaultEntry.count).to eq(0)
    end

    it "replaces a value" do
      entry = VaultEntry.create!(namespace: "github", key: "token", encrypted_value: "old-value-1")

      patch vault_entry_path(entry), params: { vault_entry: { value: "new-value-2" } }

      expect(response).to redirect_to(vault_entries_path)
      expect(entry.reload.value).to eq("new-value-2")
    end

    it "rejects a blank replacement" do
      entry = VaultEntry.create!(namespace: "github", key: "token", encrypted_value: "old-value-1")

      patch vault_entry_path(entry), params: { vault_entry: { value: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(entry.reload.value).to eq("old-value-1")
    end

    it "deletes an entry" do
      entry = VaultEntry.create!(namespace: "stripe", key: "sk", encrypted_value: "secret-value")

      expect { delete vault_entry_path(entry) }.to change(VaultEntry, :count).by(-1)
      expect(response).to redirect_to(vault_entries_path)
    end

    it "does not touch agent-scoped entries" do
      entry = VaultEntry.create!(namespace: "stripe", key: "sk", encrypted_value: "secret-value", agent: create(:agent))

      delete vault_entry_path(entry)

      expect(response).to have_http_status(:not_found)
      expect(VaultEntry.exists?(entry.id)).to be(true)
    end

    it "never puts a stored value in any response body" do
      entry = VaultEntry.create!(namespace: "openai", key: "api_key", encrypted_value: secret)
      bodies = []
      get vault_entries_path
      bodies << response.body
      get edit_vault_entry_path(entry)
      bodies << response.body
      patch vault_entry_path(entry), params: { vault_entry: { value: "" } }
      bodies << response.body
      post vault_entries_path, params: { vault_entry: { namespace: "openai", key: "api_key", value: "different-secret-9" } }
      bodies << response.body

      expect(bodies.join).not_to include(secret)
    end
  end

  describe "as a viewer" do
    before { sign_in create(:user, :viewer) }

    it "is denied" do
      get vault_entries_path
      expect(response).to redirect_to(root_path)
    end
  end
end
