# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::AgentConfig::EgressPolicySerializer do
  def call(agent)
    described_class.call(agent: agent)
  end

  describe "blank / empty policy" do
    it "returns nil when egress_policy is an empty hash" do
      agent = create(:agent, name: "Mando", role: "Engineer", egress_policy: {})
      expect(call(agent)).to be_nil
    end

    it "returns nil when mode is blank" do
      agent = create(:agent, name: "Mando", role: "Engineer",
        egress_policy: { "rules" => [] })
      expect(call(agent)).to be_nil
    end
  end

  describe "mode only" do
    it "serializes a policy with mode and no rules" do
      agent = create(:agent, name: "Mando", role: "Engineer",
        egress_policy: { "mode" => "disabled" })
      result = call(agent)
      expect(result).to eq({ "mode" => "disabled" })
    end
  end

  describe "rules" do
    it "includes rules when present" do
      policy = { "mode" => "allowlist", "rules" => [{ "pattern" => "*.example.com" }] }
      agent  = create(:agent, name: "Mando", role: "Engineer", egress_policy: policy)
      result = call(agent)
      expect(result["rules"]).to eq([{ "pattern" => "*.example.com" }])
    end

    it "includes port in rule when set" do
      policy = { "mode" => "allowlist", "rules" => [{ "pattern" => "api.co", "port" => 443 }] }
      agent  = create(:agent, name: "Mando", role: "Engineer", egress_policy: policy)
      result = call(agent)
      expect(result["rules"].first).to eq({ "pattern" => "api.co", "port" => 443 })
    end

    it "omits rules key when rules array is empty" do
      policy = { "mode" => "blocklist", "rules" => [] }
      agent  = create(:agent, name: "Mando", role: "Engineer", egress_policy: policy)
      result = call(agent)
      expect(result).not_to have_key("rules")
    end
  end

  describe "log_blocked" do
    it "includes log_blocked when true" do
      policy = { "mode" => "blocklist", "log_blocked" => true }
      agent  = create(:agent, name: "Mando", role: "Engineer", egress_policy: policy)
      expect(call(agent)["log_blocked"]).to be true
    end

    it "includes log_blocked when false" do
      policy = { "mode" => "allowlist", "log_blocked" => false }
      agent  = create(:agent, name: "Mando", role: "Engineer", egress_policy: policy)
      expect(call(agent)["log_blocked"]).to be false
    end

    it "omits log_blocked when not set" do
      policy = { "mode" => "allowlist" }
      agent  = create(:agent, name: "Mando", role: "Engineer", egress_policy: policy)
      expect(call(agent)).not_to have_key("log_blocked")
    end
  end
end
