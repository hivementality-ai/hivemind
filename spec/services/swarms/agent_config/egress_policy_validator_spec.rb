# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::AgentConfig::EgressPolicyValidator do
  def call(policy)
    described_class.call(policy: policy)
  end

  describe "nil / blank input" do
    it "succeeds on nil" do
      expect(call(nil)).to be_success
    end

    it "succeeds on empty hash" do
      expect(call({})).to be_success
    end
  end

  describe "type check" do
    it "fails when policy is a string" do
      result = call("allowlist")
      expect(result).to be_error
      expect(result.payload[:errors]).to include("egress_policy must be an object")
    end

    it "fails when policy is an array" do
      result = call([])
      expect(result).to be_error
    end
  end

  describe "mode validation" do
    %w[allowlist blocklist disabled].each do |valid_mode|
      it "succeeds with mode '#{valid_mode}'" do
        expect(call({ "mode" => valid_mode })).to be_success
      end
    end

    it "fails with an invalid mode" do
      result = call({ "mode" => "deny-all" })
      expect(result).to be_error
      expect(result.payload[:errors].first).to match(/mode.*invalid/)
    end
  end

  describe "rules validation" do
    it "succeeds when rules is absent" do
      expect(call({ "mode" => "allowlist" })).to be_success
    end

    it "fails when rules is not an array" do
      result = call({ "mode" => "allowlist", "rules" => "bad" })
      expect(result).to be_error
      expect(result.payload[:errors]).to include("egress_policy.rules must be an array")
    end

    it "fails when a rule is missing a pattern" do
      result = call({ "mode" => "allowlist", "rules" => [{ "port" => 443 }] })
      expect(result).to be_error
      expect(result.payload[:errors].first).to match(/rules\[0\].*pattern/)
    end

    it "succeeds with a valid rule" do
      result = call({ "mode" => "allowlist", "rules" => [{ "pattern" => "*.example.com" }] })
      expect(result).to be_success
    end

    it "fails when rule port is out of range" do
      result = call({ "mode" => "blocklist", "rules" => [{ "pattern" => "evil.com", "port" => 99_999 }] })
      expect(result).to be_error
      expect(result.payload[:errors].first).to match(/port.*1 and 65535/)
    end

    it "fails when rule port is zero" do
      result = call({ "mode" => "blocklist", "rules" => [{ "pattern" => "evil.com", "port" => 0 }] })
      expect(result).to be_error
    end

    it "succeeds with a valid port" do
      result = call({ "mode" => "allowlist", "rules" => [{ "pattern" => "api.example.com", "port" => 443 }] })
      expect(result).to be_success
    end
  end

  describe "log_blocked validation" do
    it "succeeds when log_blocked is true" do
      expect(call({ "mode" => "blocklist", "log_blocked" => true })).to be_success
    end

    it "succeeds when log_blocked is false" do
      expect(call({ "mode" => "blocklist", "log_blocked" => false })).to be_success
    end

    it "fails when log_blocked is a string" do
      result = call({ "mode" => "blocklist", "log_blocked" => "yes" })
      expect(result).to be_error
      expect(result.payload[:errors]).to include("egress_policy.log_blocked must be a boolean")
    end
  end

  describe "collects multiple errors" do
    it "returns all errors when multiple rules are invalid" do
      result = call({
        "mode"  => "allowlist",
        "rules" => [
          { "port" => 443 },        # missing pattern
          { "pattern" => "ok.com" } # valid
        ]
      })
      expect(result).to be_error
      expect(result.payload[:errors].size).to eq(1) # one bad rule
    end
  end
end
