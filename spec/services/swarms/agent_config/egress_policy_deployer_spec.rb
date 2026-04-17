# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::AgentConfig::EgressPolicyDeployer do
  def call(agent:, policy:)
    described_class.call(agent: agent, policy: policy)
  end

  describe "nil / blank policy" do
    it "is a no-op and succeeds" do
      agent = create(:agent, name: "Mando", role: "Engineer")
      result = call(agent: agent, policy: nil)
      expect(result).to be_success
      expect(result.payload[:applied]).to be false
    end

    it "leaves existing egress_policy unchanged" do
      existing_policy = { "mode" => "blocklist", "rules" => [] }
      agent = create(:agent, name: "Mando", role: "Engineer", egress_policy: existing_policy)
      call(agent: agent, policy: nil)
      expect(agent.reload.egress_policy).to eq(existing_policy)
    end
  end

  describe "valid policy" do
    it "applies the policy to the agent" do
      agent  = create(:agent, name: "Mando", role: "Engineer", egress_policy: {})
      policy = { "mode" => "allowlist", "rules" => [{ "pattern" => "api.example.com" }] }

      result = call(agent: agent, policy: policy)

      expect(result).to be_success
      expect(result.payload[:applied]).to be true
      expect(agent.reload.egress_policy).to eq(policy.stringify_keys)
    end

    it "overwrites a pre-existing policy" do
      old_policy = { "mode" => "blocklist", "rules" => [] }
      new_policy = { "mode" => "allowlist", "rules" => [{ "pattern" => "safe.io" }] }
      agent = create(:agent, name: "Mando", role: "Engineer", egress_policy: old_policy)

      call(agent: agent, policy: new_policy)

      expect(agent.reload.egress_policy).to include("mode" => "allowlist")
    end
  end

  describe "invalid policy" do
    it "returns an error without updating the agent" do
      agent = create(:agent, name: "Mando", role: "Engineer", egress_policy: {})
      result = call(agent: agent, policy: { "mode" => "invalid-mode" })

      expect(result).to be_error
      expect(result.message).to match(/invalid/)
      expect(agent.reload.egress_policy).to eq({})
    end
  end
end
