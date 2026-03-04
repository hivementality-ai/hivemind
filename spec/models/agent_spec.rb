# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent, type: :model do
  describe "slug generation and validation" do
    it "generates a slug from agent name on save" do
      agent = Agent.create!(name: "Test Agent", role: "Helper")
      expect(agent.slug).to eq("test_agent")
    end

    it "generates slug with special characters converted" do
      agent = Agent.create!(name: "alice's-research_v2", role: "Helper")
      expect(agent.slug).to eq("alice_s-research_v2")
    end

    it "generates slug with uppercase converted to lowercase" do
      agent = Agent.create!(name: "RESEARCH BOT", role: "Helper")
      expect(agent.slug).to eq("research_bot")
    end

    it "generates slug from name with multiple spaces" do
      agent = Agent.create!(name: "My   Long   Agent   Name", role: "Helper")
      expect(agent.slug).to eq("my_long_agent_name")
    end

    it "does not regenerate slug if name changes after creation" do
      agent = Agent.create!(name: "Test Agent", role: "Helper")
      original_slug = agent.slug

      agent.update!(name: "New Name")
      expect(agent.slug).to eq(original_slug)
    end

    it "auto-generates slug if not provided" do
      agent = Agent.new(name: "Test Agent", role: "Helper")
      agent.valid?
      expect(agent.slug).to eq("test_agent")
    end

    it "enforces unique slug (case-insensitive)" do
      Agent.create!(name: "Test Agent", role: "Helper")

      duplicate = Agent.new(name: "test_agent", role: "Helper")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:slug]).to include(/taken/)
    end

    it "enforces unique slug with different cases" do
      Agent.create!(name: "Test Agent", role: "Helper")

      duplicate = Agent.new(name: "TEST AGENT", role: "Helper")
      expect(duplicate).not_to be_valid
    end
  end

  describe ".find_by_slug" do
    it "finds agent by exact slug" do
      agent = Agent.create!(name: "Test Agent", role: "Helper")
      found = Agent.find_by_slug("test_agent")
      expect(found).to eq(agent)
    end

    it "finds agent by slug case-insensitively" do
      agent = Agent.create!(name: "Test Agent", role: "Helper")

      expect(Agent.find_by_slug("Test_Agent")).to eq(agent)
      expect(Agent.find_by_slug("TEST_AGENT")).to eq(agent)
      expect(Agent.find_by_slug("test_agent")).to eq(agent)
    end

    it "raises RecordNotFound for non-existent slug" do
      expect { Agent.find_by_slug("nonexistent") }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "egress policy" do
    describe "validation" do
      it "accepts empty egress_policy" do
        agent = build(:agent, egress_policy: {})
        expect(agent).to be_valid
      end

      it "accepts valid allowlist policy" do
        agent = build(:agent, egress_policy: {
          "mode" => "allowlist",
          "rules" => [ { "pattern" => "*.github.com" } ],
          "log_blocked" => true
        })
        expect(agent).to be_valid
      end

      it "accepts valid blocklist policy" do
        agent = build(:agent, egress_policy: {
          "mode" => "blocklist",
          "rules" => [ { "pattern" => "evil.com" } ],
          "log_blocked" => false
        })
        expect(agent).to be_valid
      end

      it "accepts disabled mode" do
        agent = build(:agent, egress_policy: { "mode" => "disabled" })
        expect(agent).to be_valid
      end

      it "rejects invalid mode" do
        agent = build(:agent, egress_policy: { "mode" => "yolo" })
        expect(agent).not_to be_valid
        expect(agent.errors[:egress_policy].first).to include("invalid mode")
      end

      it "rejects rules without pattern" do
        agent = build(:agent, egress_policy: {
          "mode" => "allowlist",
          "rules" => [ { "port" => 443 } ]
        })
        expect(agent).not_to be_valid
        expect(agent.errors[:egress_policy].first).to include("must have a pattern")
      end

      it "rejects non-array rules" do
        agent = build(:agent, egress_policy: {
          "mode" => "allowlist",
          "rules" => "not-an-array"
        })
        expect(agent).not_to be_valid
        expect(agent.errors[:egress_policy].first).to include("must be an array")
      end
    end

    describe "#effective_egress_policy" do
      it "returns empty hash with indifferent access for no policy" do
        agent = build(:agent, egress_policy: {})
        result = agent.effective_egress_policy
        expect(result).to be_a(ActiveSupport::HashWithIndifferentAccess)
      end

      it "returns policy with indifferent access" do
        agent = build(:agent, egress_policy: { "mode" => "allowlist" })
        expect(agent.effective_egress_policy[:mode]).to eq("allowlist")
        expect(agent.effective_egress_policy["mode"]).to eq("allowlist")
      end
    end

    describe "#egress_enforced?" do
      it "returns false for empty policy" do
        agent = build(:agent, egress_policy: {})
        expect(agent.egress_enforced?).to be false
      end

      it "returns false for disabled mode" do
        agent = build(:agent, egress_policy: { "mode" => "disabled" })
        expect(agent.egress_enforced?).to be false
      end

      it "returns true for allowlist mode" do
        agent = build(:agent, egress_policy: { "mode" => "allowlist", "rules" => [] })
        expect(agent.egress_enforced?).to be true
      end

      it "returns true for blocklist mode" do
        agent = build(:agent, egress_policy: { "mode" => "blocklist", "rules" => [] })
        expect(agent.egress_enforced?).to be true
      end
    end

    describe "virtual attributes" do
      it "composes egress_policy from virtual attrs" do
        agent = build(:agent,
          egress_policy_mode: "allowlist",
          egress_policy_rules: "*.github.com\napi.example.com",
          egress_policy_log_blocked: "true"
        )
        agent.valid?

        expect(agent.egress_policy["mode"]).to eq("allowlist")
        expect(agent.egress_policy["rules"]).to eq([
          { "pattern" => "*.github.com" },
          { "pattern" => "api.example.com" }
        ])
        expect(agent.egress_policy["log_blocked"]).to be true
      end

      it "skips composition when mode is blank" do
        agent = build(:agent, egress_policy: { "mode" => "blocklist", "rules" => [] })
        agent.egress_policy_mode = ""
        agent.valid?

        # Original policy preserved since virtual attr mode is blank
        expect(agent.egress_policy["mode"]).to eq("blocklist")
      end
    end
  end

  describe ".by_slug scope" do
    it "filters agents by slug case-insensitively" do
      agent1 = Agent.create!(name: "Test Agent", role: "Helper")
      Agent.create!(name: "Other Agent", role: "Helper")

      result = Agent.by_slug("TEST_AGENT")
      expect(result).to include(agent1)
      expect(result.count).to eq(1)
    end
  end
end
