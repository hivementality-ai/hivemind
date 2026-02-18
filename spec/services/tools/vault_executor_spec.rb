# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::VaultExecutor, type: :service do
  let(:agent) { create(:agent, name: "TestAgent") }

  def execute(input)
    described_class.new(agent: agent, input: input).call
  end

  describe "unknown action" do
    it "returns failure with supported actions" do
      response = execute("action" => "nope")
      expect(response.success?).to be false
      expect(response.error).to include("Unknown vault action")
    end
  end

  describe "read action" do
    it "returns redacted value for existing key" do
      create(:vault_entry, namespace: "providers", key: "openai_api_key", value: "sk-proj-abc123xyz789", agent_id: nil)
      response = execute("action" => "read", "namespace" => "providers", "key" => "openai_api_key")

      expect(response.success?).to be true
      expect(response.data[:redacted_value]).not_to eq("sk-proj-abc123xyz789")
      expect(response.data[:redacted_value]).to include("sk-proj-")
      expect(response.data[:redacted_value]).to include("z789")
    end

    it "returns failure for missing key" do
      response = execute("action" => "read", "namespace" => "nope", "key" => "nope")
      expect(response.success?).to be false
      expect(response.error).to include("not found")
    end

    it "requires namespace" do
      response = execute("action" => "read", "namespace" => "", "key" => "x")
      expect(response.success?).to be false
    end

    it "requires key" do
      response = execute("action" => "read", "namespace" => "x", "key" => "")
      expect(response.success?).to be false
    end
  end

  describe "exists action" do
    it "returns true when key exists" do
      create(:vault_entry, namespace: "test", key: "mykey", agent_id: nil)
      response = execute("action" => "exists", "namespace" => "test", "key" => "mykey")

      expect(response.success?).to be true
      expect(response.data[:exists]).to be true
      expect(response.data[:output]).to include("✅")
    end

    it "returns false when key missing" do
      response = execute("action" => "exists", "namespace" => "test", "key" => "nope")

      expect(response.success?).to be true
      expect(response.data[:exists]).to be false
      expect(response.data[:output]).to include("❌")
    end
  end

  describe "write action" do
    it "creates a pending write confirmation" do
      response = execute(
        "action" => "write",
        "namespace" => "providers",
        "key" => "slack_token",
        "value" => "xoxb-test-token",
        "purpose" => "Slack bot auth",
        "tool_binding" => "slack"
      )

      expect(response.success?).to be true
      expect(response.data[:status]).to eq("pending_confirmation")
      expect(response.data[:confirmation_id]).to be_present
    end

    it "requires namespace, key, value" do
      expect(execute("action" => "write", "namespace" => "", "key" => "k", "value" => "v").success?).to be false
      expect(execute("action" => "write", "namespace" => "n", "key" => "", "value" => "v").success?).to be false
      expect(execute("action" => "write", "namespace" => "n", "key" => "k", "value" => "").success?).to be false
    end
  end

  describe "confirm_write action" do
    it "persists entry after confirmation" do
      # Stage 1
      write_resp = execute(
        "action" => "write",
        "namespace" => "test",
        "key" => "secret",
        "value" => "my-secret-value",
        "purpose" => "testing"
      )
      confirmation_id = write_resp.data[:confirmation_id]

      # Stage 2
      confirm_resp = execute("action" => "confirm_write", "confirmation_id" => confirmation_id)

      expect(confirm_resp.success?).to be true
      expect(confirm_resp.data[:output]).to include("stored ✅")
      expect(VaultEntry.find_by(namespace: "test", key: "secret")).to be_present
    end

    it "fails with missing confirmation_id" do
      response = execute("action" => "confirm_write", "confirmation_id" => "")
      expect(response.success?).to be false
    end

    it "fails with invalid confirmation_id" do
      response = execute("action" => "confirm_write", "confirmation_id" => "bogus-id")
      expect(response.success?).to be false
    end
  end

  describe "list_keys action" do
    it "lists keys in a namespace" do
      create(:vault_entry, namespace: "providers", key: "key1", agent_id: nil)
      create(:vault_entry, namespace: "providers", key: "key2", agent_id: nil)
      create(:vault_entry, namespace: "other", key: "key3", agent_id: nil)

      response = execute("action" => "list_keys", "namespace" => "providers")

      expect(response.success?).to be true
      expect(response.data[:count]).to eq(2)
      expect(response.data[:output]).to include("key1")
      expect(response.data[:output]).to include("key2")
      expect(response.data[:output]).not_to include("key3")
    end

    it "lists all keys when no namespace given" do
      create(:vault_entry, namespace: "a", key: "k1", agent_id: nil)
      create(:vault_entry, namespace: "b", key: "k2", agent_id: nil)

      response = execute("action" => "list_keys")

      expect(response.success?).to be true
      expect(response.data[:count]).to eq(2)
    end

    it "returns empty message when vault is empty" do
      response = execute("action" => "list_keys")
      expect(response.success?).to be true
      expect(response.data[:output]).to include("empty")
    end
  end

  describe "check_tool action" do
    it "reports ready when credentials exist" do
      tool = create(:tool, name: "jira", required_credentials: [
        { "namespace" => "jira", "key" => "api_token", "description" => "Jira API Token" }
      ])
      create(:vault_entry, namespace: "jira", key: "api_token", agent_id: nil)

      response = execute("action" => "check_tool", "tool_name" => "jira")

      expect(response.success?).to be true
      expect(response.data[:ready]).to be true
      expect(response.data[:output]).to include("✅")
    end

    it "reports missing credentials" do
      create(:tool, name: "jira", required_credentials: [
        { "namespace" => "jira", "key" => "api_token", "description" => "Jira API Token" }
      ])

      response = execute("action" => "check_tool", "tool_name" => "jira")

      expect(response.success?).to be true
      expect(response.data[:ready]).to be false
      expect(response.data[:missing]).to be_present
    end

    it "fails for unknown tool" do
      response = execute("action" => "check_tool", "tool_name" => "doesnt_exist")
      expect(response.success?).to be false
    end
  end
end
