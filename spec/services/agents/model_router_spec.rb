# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::ModelRouter do
  describe ".auto_supported?" do
    it "returns true for the big two providers" do
      expect(described_class.auto_supported?("anthropic")).to be(true)
      expect(described_class.auto_supported?("openai")).to be(true)
    end

    it "returns false for everyone else" do
      expect(described_class.auto_supported?("ollama")).to be(false)
      expect(described_class.auto_supported?("openai_compatible")).to be(false)
      expect(described_class.auto_supported?("")).to be(false)
    end
  end

  describe ".detect_task" do
    it "picks architecture from keyword" do
      expect(described_class.detect_task("help me design the multi-file architecture")).to eq("architecture")
    end

    it "picks security_review from audit keyword" do
      expect(described_class.detect_task("run a security audit")).to eq("security_review")
    end

    it "picks file_search from grep in recent tools when message is neutral" do
      expect(described_class.detect_task("just check", recent_tools: [ "file_read", "grep" ])).to eq("file_search")
    end

    it "falls back to chatting when nothing matches" do
      expect(described_class.detect_task("hey", recent_tools: [])).to eq("chatting")
    end
  end

  describe ".tier_for" do
    it "maps chatting to cheap tier" do
      expect(described_class.tier_for("chatting")).to eq("cheap")
    end

    it "maps bug_fix to mid tier" do
      expect(described_class.tier_for("bug_fix")).to eq("mid")
    end

    it "maps architecture to top tier" do
      expect(described_class.tier_for("architecture")).to eq("top")
    end

    it "defaults unknown task to mid" do
      expect(described_class.tier_for("undefined_task")).to eq("mid")
    end
  end

  describe ".route" do
    it "returns nil for unsupported providers" do
      expect(described_class.route(provider: "ollama", message_text: "hi")).to be_nil
    end

    it "routes security keyword to anthropic opus" do
      expect(described_class.route(provider: "anthropic", message_text: "perform a security audit on the auth flow"))
        .to eq(LlmModelRegistry::Anthropic::DEFAULT_TOP)
    end

    it "routes chitchat to anthropic haiku" do
      expect(described_class.route(provider: "anthropic", message_text: "hey marty you there")).to eq("claude-haiku-4-5")
    end

    it "routes bug-fix keyword to openai mid tier" do
      expect(described_class.route(provider: "openai", message_text: "fix this bug in the controller"))
        .to eq("gpt-5.4-mini")
    end

    context "with custom rules in the Setting" do
      before do
        Setting.set("model_router_rules", {
          "anthropic" => { "tiers" => { "cheap" => "claude-haiku-4-5", "mid" => "claude-sonnet-4-5", "top" => "claude-opus-4-6" } }
        }.to_json)
      end

      after { Setting.where(key: "model_router_rules").delete_all }

      it "respects the custom mid-tier model" do
        expect(described_class.route(provider: "anthropic", message_text: "fix this bug")).to eq("claude-sonnet-4-5")
      end
    end

    context "when custom rules are malformed JSON" do
      before { Setting.set("model_router_rules", "{not valid json") }
      after  { Setting.where(key: "model_router_rules").delete_all }

      it "falls back to defaults without crashing" do
        expect(described_class.route(provider: "anthropic", message_text: "hey")).to eq("claude-haiku-4-5")
      end
    end
  end
end
