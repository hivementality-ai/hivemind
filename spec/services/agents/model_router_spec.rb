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
      expect(described_class.route(provider: "anthropic", message_text: "hey marty you there")).to eq("claude-haiku-5-5")
    end

    it "routes bug-fix keyword to openai mid tier" do
      expect(described_class.route(provider: "openai", message_text: "fix this bug in the controller"))
        .to eq("gpt-6.1-terra")
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
        expect(described_class.route(provider: "anthropic", message_text: "hey")).to eq("claude-haiku-5-5")
      end
    end
  end

  describe ".local_pick" do
    let(:studio_ok) { { status: :green, checks: [ { key: "studio", ok: true } ], checked_at: Time.current } }
    let(:studio_down) { { status: :amber, checks: [ { key: "studio", ok: false } ], checked_at: Time.current } }
    let!(:ollama) do
      create(:provider_config, name: "studio", adapter_type: "ollama", enabled: true,
                               model_definitions: [ { "id" => "qwen3:8b" } ])
    end

    before { allow(Platform::HealthLight).to receive(:snapshot).and_return(studio_ok) }

    it "routes a cheap task to the enabled, healthy Ollama provider" do
      pick = described_class.local_pick(message_text: "hey there")

      expect(pick).to eq(config: ollama, model: "qwen3:8b")
    end

    it "stays on Claude when Ollama is disabled" do
      ollama.update!(enabled: false)

      expect(described_class.local_pick(message_text: "hey there")).to be_nil
    end

    it "stays on Claude when Ollama's last health check failed" do
      allow(Platform::HealthLight).to receive(:snapshot).and_return(studio_down)

      expect(described_class.local_pick(message_text: "hey there")).to be_nil
    end

    it "stays on Claude when no health snapshot exists yet" do
      allow(Platform::HealthLight).to receive(:snapshot).and_return(nil)

      expect(described_class.local_pick(message_text: "hey there")).to be_nil
    end

    it "keeps heavier tiers on Claude" do
      expect(described_class.local_pick(message_text: "fix this bug")).to be_nil
      expect(described_class.local_pick(message_text: "design the system")).to be_nil
    end

    it "keeps turns with tools on Claude" do
      expect(described_class.local_pick(message_text: "hey there", tools: [ :a_tool ])).to be_nil
    end

    it "keeps turns with images on Claude" do
      expect(described_class.local_pick(message_text: "hey there", images: true)).to be_nil
    end

    it "keeps long messages on Claude" do
      long = "hey " * described_class::LOCAL_MAX_CHARS

      expect(described_class.local_pick(message_text: long)).to be_nil
    end
  end
end
