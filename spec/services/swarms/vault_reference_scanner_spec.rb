# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::VaultReferenceScanner do
  # ---------------------------------------------------------------------------
  # No vault references
  # ---------------------------------------------------------------------------

  describe "when the manifest has no vault references" do
    it "succeeds with empty vault_refs and missing lists" do
      result = described_class.call(manifest: { "name" => "Simple Swarm", "swarm_version" => "1.0" })

      expect(result).to be_success
      expect(result.payload[:vault_refs]).to eq([])
      expect(result.payload[:missing]).to eq([])
    end

    it "ignores strings that merely contain the word vault" do
      result = described_class.call(manifest: { "description" => "Stores secrets in the vault" })

      expect(result).to be_success
      expect(result.payload[:vault_refs]).to eq([])
    end
  end

  # ---------------------------------------------------------------------------
  # Vault reference collection
  # ---------------------------------------------------------------------------

  describe "vault reference collection" do
    it "detects a vault: reference at the top level" do
      create(:vault_entry, namespace: "global", key: "token")

      result = described_class.call(manifest: { "api_key" => "vault:global/token" })

      expect(result).to be_success
      expect(result.payload[:vault_refs]).to include("global/token")
    end

    it "detects vault: references in nested hashes" do
      create(:vault_entry, namespace: "slack", key: "bot_token")

      manifest = {
        "mcp_servers" => [
          { "name" => "my-mcp", "env_vars" => { "TOKEN" => "vault:slack/bot_token" } }
        ]
      }

      result = described_class.call(manifest:)

      expect(result).to be_success
      expect(result.payload[:vault_refs]).to include("slack/bot_token")
    end

    it "detects vault: references in arrays" do
      create(:vault_entry, namespace: "infra", key: "ssh_key")

      manifest = { "tags" => ["env-prod", "vault:infra/ssh_key"] }

      result = described_class.call(manifest:)

      expect(result).to be_success
      expect(result.payload[:vault_refs]).to include("infra/ssh_key")
    end

    it "collects multiple distinct vault references" do
      create(:vault_entry, namespace: "slack", key: "token")
      create(:vault_entry, namespace: "openai", key: "api_key")

      manifest = {
        "channels" => [{ "webhook" => "vault:slack/token" }],
        "api_integrations" => [{ "auth" => "vault:openai/api_key" }]
      }

      result = described_class.call(manifest:)

      expect(result).to be_success
      expect(result.payload[:vault_refs]).to contain_exactly("openai/api_key", "slack/token")
    end

    it "deduplicates the same vault path appearing multiple times" do
      create(:vault_entry, namespace: "secrets", key: "shared_token")

      manifest = {
        "a" => "vault:secrets/shared_token",
        "b" => "vault:secrets/shared_token"
      }

      result = described_class.call(manifest:)

      expect(result).to be_success
      expect(result.payload[:vault_refs]).to eq(["secrets/shared_token"])
    end

    it "returns vault_refs sorted alphabetically" do
      create(:vault_entry, namespace: "z_ns", key: "key")
      create(:vault_entry, namespace: "a_ns", key: "key")

      manifest = {
        "x" => "vault:z_ns/key",
        "y" => "vault:a_ns/key"
      }

      result = described_class.call(manifest:)

      expect(result).to be_success
      expect(result.payload[:vault_refs]).to eq(["a_ns/key", "z_ns/key"])
    end
  end

  # ---------------------------------------------------------------------------
  # Missing vault entries
  # ---------------------------------------------------------------------------

  describe "missing vault entries" do
    it "returns error when a vault reference has no matching VaultEntry" do
      result = described_class.call(manifest: { "secret" => "vault:missing/token" })

      expect(result).to be_error
      expect(result.message).to include("missing/token")
      expect(result.payload[:missing]).to eq(["missing/token"])
    end

    it "reports all missing vault entries, not just the first" do
      manifest = {
        "a" => "vault:ns/key_a",
        "b" => "vault:ns/key_b"
      }

      result = described_class.call(manifest:)

      expect(result).to be_error
      expect(result.payload[:missing]).to contain_exactly("ns/key_a", "ns/key_b")
    end

    it "only reports missing entries, not present ones" do
      create(:vault_entry, namespace: "ns", key: "present")

      manifest = {
        "a" => "vault:ns/present",
        "b" => "vault:ns/absent"
      }

      result = described_class.call(manifest:)

      expect(result).to be_error
      expect(result.payload[:missing]).to eq(["ns/absent"])
      expect(result.payload[:vault_refs]).to contain_exactly("ns/absent", "ns/present")
    end

    it "returns missing sorted alphabetically" do
      manifest = {
        "x" => "vault:z_ns/key",
        "y" => "vault:a_ns/key"
      }

      result = described_class.call(manifest:)

      expect(result).to be_error
      expect(result.payload[:missing]).to eq(["a_ns/key", "z_ns/key"])
    end
  end

  # ---------------------------------------------------------------------------
  # vault: format validation
  # ---------------------------------------------------------------------------

  describe "vault: reference format" do
    it "requires the namespace/key slash separator" do
      # "vault:noSlash" does not match — ignored as not a valid vault ref
      result = described_class.call(manifest: { "bad" => "vault:noslash" })

      expect(result).to be_success
      expect(result.payload[:vault_refs]).to eq([])
    end

    it "splits on the first slash only (key may contain slashes)" do
      create(:vault_entry, namespace: "ns", key: "deep/path")

      result = described_class.call(manifest: { "val" => "vault:ns/deep/path" })

      expect(result).to be_success
      expect(result.payload[:vault_refs]).to eq(["ns/deep/path"])
    end

    it "does not treat plain strings starting with 'vault:' but no path as refs" do
      result = described_class.call(manifest: { "val" => "vault:" })

      expect(result).to be_success
      expect(result.payload[:vault_refs]).to eq([])
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  describe "edge cases" do
    it "handles an empty manifest" do
      result = described_class.call(manifest: {})

      expect(result).to be_success
      expect(result.payload[:vault_refs]).to eq([])
    end

    it "handles nil values in the manifest without raising" do
      result = described_class.call(manifest: { "key" => nil, "other" => "value" })

      expect(result).to be_success
    end

    it "handles integer and boolean values without raising" do
      result = described_class.call(manifest: { "count" => 5, "flag" => true })

      expect(result).to be_success
    end
  end
end
