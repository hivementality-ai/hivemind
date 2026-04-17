# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::SecretStripper do
  def call(manifest)
    described_class.call(manifest: manifest)
  end

  # ---------------------------------------------------------------------------
  # Result contract
  # ---------------------------------------------------------------------------

  describe "result contract" do
    it "always returns a successful ServiceResponse" do
      result = call({})
      expect(result).to be_success
    end

    it "payload includes manifest, stripped_count, and stripped_paths" do
      result = call({ "name" => "clean" })
      expect(result.payload).to include(:manifest, :stripped_count, :stripped_paths)
    end

    it "stripped_count is 0 when nothing is stripped" do
      result = call({ "name" => "My Team", "description" => "A fine swarm" })
      expect(result.payload[:stripped_count]).to eq(0)
      expect(result.payload[:stripped_paths]).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Secret field names — stripped when value looks like a secret
  # ---------------------------------------------------------------------------

  describe "secret field name detection" do
    %w[api_key api_secret token password secret access_token refresh_token
       auth_token private_key client_secret webhook_secret signing_secret].each do |field|
      it "strips field named '#{field}' when value is non-trivial" do
        manifest = { field => "abc123xyz9876secret" }
        result   = call(manifest)
        expect(result.payload[:manifest][field]).to start_with("vault:")
        expect(result.payload[:stripped_count]).to eq(1)
      end
    end

    it "does not strip a secret field whose value is very short (< 8 chars)" do
      result = call({ "token" => "abc" })
      expect(result.payload[:manifest]["token"]).to eq("abc")
    end

    it "does not strip a secret field whose value is a URL" do
      result = call({ "api_key" => "https://example.com/key" })
      expect(result.payload[:manifest]["api_key"]).to eq("https://example.com/key")
    end

    it "does not strip a secret field whose value is already a vault: reference" do
      existing = "vault:some/existing"
      result = call({ "api_key" => existing })
      expect(result.payload[:manifest]["api_key"]).to eq(existing)
      expect(result.payload[:stripped_count]).to eq(0)
    end

    it "does not strip a plain prose field like 'description'" do
      result = call({ "description" => "This is a perfectly normal description." })
      expect(result.payload[:manifest]["description"]).to eq("This is a perfectly normal description.")
    end
  end

  # ---------------------------------------------------------------------------
  # Secret value patterns — stripped regardless of field name
  # ---------------------------------------------------------------------------

  describe "secret value pattern detection" do
    it "strips OpenAI-style sk- keys" do
      manifest = { "config" => "sk-abcdefghijklmnopqrstu" }
      result   = call(manifest)
      expect(result.payload[:manifest]["config"]).to start_with("vault:")
    end

    it "strips GitHub personal access tokens (ghp_)" do
      manifest = { "note" => "gh" + "p_" + ("a" * 36) }
      result   = call(manifest)
      expect(result.payload[:manifest]["note"]).to start_with("vault:")
    end

    it "strips Slack bot tokens (xoxb-)" do
      manifest = { "integration" => "xo" + "xb-123456789-abcdefghijklmn" }
      result   = call(manifest)
      expect(result.payload[:manifest]["integration"]).to start_with("vault:")
    end

    it "strips JWT-shaped strings" do
      jwt = "eyJhbGciOiJIUzI1NiJ9" + "." + "eyJzdWIiOiJ1c2VyIn0" + "." + "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
      result = call({ "auth" => jwt })
      expect(result.payload[:manifest]["auth"]).to start_with("vault:")
    end

    it "does not strip plain readable strings that happen to be longish" do
      result = call({ "soul" => "You are a helpful assistant who writes clean code." })
      expect(result.payload[:manifest]["soul"]).to eq("You are a helpful assistant who writes clean code.")
    end
  end

  # ---------------------------------------------------------------------------
  # Nested structures
  # ---------------------------------------------------------------------------

  describe "nested Hash and Array traversal" do
    it "strips secrets nested inside a Hash" do
      manifest = {
        "mcp_servers" => [
          { "name" => "github", "env" => { "api_key" => "sk-toolongvalue12345678" } }
        ]
      }
      result = call(manifest)
      stripped = result.payload[:manifest]["mcp_servers"].first["env"]["api_key"]
      expect(stripped).to start_with("vault:")
    end

    it "preserves non-secret keys in nested hashes" do
      manifest = {
        "agent" => { "name" => "Mando", "api_key" => "sk-abcdefghijklmnopqrstu" }
      }
      result = call(manifest)
      expect(result.payload[:manifest]["agent"]["name"]).to eq("Mando")
      expect(result.payload[:manifest]["agent"]["api_key"]).to start_with("vault:")
    end

    it "handles arrays of strings without error" do
      manifest = { "tags" => %w[ruby rails swarm] }
      result = call(manifest)
      expect(result.payload[:manifest]["tags"]).to eq(%w[ruby rails swarm])
    end

    it "reports the correct dot-path for deeply nested secrets" do
      manifest = { "agents" => [ { "config" => { "api_key" => "sk-deepvalue123456789012" } } ] }
      result   = call(manifest)
      expect(result.payload[:stripped_paths]).to include("agents.0.config.api_key")
    end
  end

  # ---------------------------------------------------------------------------
  # Vault reference format
  # ---------------------------------------------------------------------------

  describe "vault reference format" do
    it "uses vault:swarm_export/<path> convention" do
      result = call({ "api_key" => "sk-abcdefghijklmnopqrstu" })
      expect(result.payload[:manifest]["api_key"]).to eq("vault:swarm_export/api_key")
    end

    it "includes the dot-notation path in the vault key" do
      manifest = { "settings" => { "token" => "sk-abcdefghijklmnopqrstu" } }
      result   = call(manifest)
      expect(result.payload[:manifest]["settings"]["token"]).to eq("vault:swarm_export/settings.token")
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  describe "edge cases" do
    it "handles an empty manifest" do
      result = call({})
      expect(result).to be_success
      expect(result.payload[:stripped_count]).to eq(0)
    end

    it "handles nil values without raising" do
      result = call({ "api_key" => nil, "name" => "x" })
      expect(result).to be_success
    end

    it "handles integer and boolean values without raising" do
      result = call({ "count" => 5, "enabled" => true })
      expect(result).to be_success
      expect(result.payload[:manifest]["count"]).to eq(5)
      expect(result.payload[:manifest]["enabled"]).to eq(true)
    end

    it "does not mutate the original manifest" do
      original = { "api_key" => "sk-abcdefghijklmnopqrstu" }.freeze
      expect { call(original) }.not_to raise_error
    end
  end
end
