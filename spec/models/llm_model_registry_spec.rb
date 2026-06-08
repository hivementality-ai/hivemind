# frozen_string_literal: true

require "rails_helper"

RSpec.describe LlmModelRegistry do
  # ── Basic structure ──────────────────────────────────────────────────────

  describe ".all" do
    it "returns an array of Model structs" do
      expect(described_class.all).to be_an(Array)
      expect(described_class.all).to all(be_a(described_class::Model))
    end

    it "is non-empty" do
      expect(described_class.all).not_to be_empty
    end

    it "has no duplicate api_ids" do
      ids = described_class.all.map(&:api_id)
      expect(ids).to eq(ids.uniq)
    end
  end

  # ── Model struct behaviour ───────────────────────────────────────────────

  describe described_class::Model do
    subject(:model) { described_class.find("claude-haiku-4-5") }

    it "exposes all required attributes" do
      expect(model.api_id).to eq("claude-haiku-4-5")
      expect(model.display_name).to eq("Claude Haiku 4.5")
      expect(model.provider).to eq("anthropic")
      expect(model.family).to eq("haiku")
      expect(model.context_window).to be_a(Integer)
      expect(model.input_cost_per_mtok).to be_a(Integer)
      expect(model.output_cost_per_mtok).to be_a(Integer)
      expect(model.status).to be_a(Symbol)
      expect(model.description).to be_a(String)
      expect(model.capabilities).to be_an(Array)
    end

    it "reports active? correctly" do
      expect(model.active?).to be true
      expect(model.deprecated?).to be false
      expect(model.sunset?).to be false
    end

    it "returns a cost_rates hash with :input and :output keys" do
      rates = model.cost_rates
      expect(rates).to have_key(:input)
      expect(rates).to have_key(:output)
      expect(rates[:input]).to be >= 0
      expect(rates[:output]).to be >= 0
    end

    it "returns a to_select_option hash with :id, :name, :desc" do
      option = model.to_select_option
      expect(option[:id]).to eq("claude-haiku-4-5")
      expect(option[:name]).to eq("Claude Haiku 4.5")
      expect(option[:desc]).to be_a(String)
    end
  end

  # ── .find / .fetch ───────────────────────────────────────────────────────

  describe ".find" do
    it "returns the model for a known api_id" do
      model = described_class.find("claude-haiku-4-5")
      expect(model).not_to be_nil
      expect(model.api_id).to eq("claude-haiku-4-5")
    end

    it "returns nil for an unknown api_id" do
      expect(described_class.find("claude-nonexistent-99")).to be_nil
    end

    it "returns nil for blank input" do
      expect(described_class.find(nil)).to be_nil
      expect(described_class.find("")).to be_nil
    end
  end

  describe ".fetch" do
    it "returns the model for a known api_id" do
      model = described_class.fetch("gpt-5.4")
      expect(model.api_id).to eq("gpt-5.4")
    end

    it "raises KeyError for an unknown api_id" do
      expect { described_class.fetch("nonexistent-model") }.to raise_error(KeyError, /nonexistent-model/)
    end
  end

  # ── Provider filtering ───────────────────────────────────────────────────

  describe ".for_provider" do
    it "returns only models for the given provider" do
      anthropic_models = described_class.for_provider("anthropic")
      expect(anthropic_models).not_to be_empty
      expect(anthropic_models).to all(satisfy { |m| m.provider == "anthropic" })
    end

    it "returns an empty array for an unknown provider" do
      expect(described_class.for_provider("unknown_provider")).to eq([])
    end
  end

  describe ".active_for_provider" do
    it "returns only active models" do
      active = described_class.active_for_provider("anthropic")
      expect(active).not_to be_empty
      expect(active).to all(satisfy(&:active?))
    end

    it "excludes deprecated models" do
      deprecated_ids = described_class.for_provider("anthropic").select(&:deprecated?).map(&:api_id)
      active_ids     = described_class.active_for_provider("anthropic").map(&:api_id)
      expect(active_ids & deprecated_ids).to be_empty
    end
  end

  describe ".supported_for_provider" do
    it "includes both active and deprecated models" do
      supported = described_class.supported_for_provider("anthropic")
      expect(supported.any?(&:active?)).to be true
      expect(supported.any?(&:deprecated?)).to be true
    end

    it "excludes sunset models" do
      sunset_ids   = described_class.for_provider("anthropic").select(&:sunset?).map(&:api_id)
      supported_ids = described_class.supported_for_provider("anthropic").map(&:api_id)
      expect(supported_ids & sunset_ids).to be_empty
    end
  end

  # ── Cost rates ───────────────────────────────────────────────────────────

  describe ".cost_rates" do
    it "returns rates for a known model" do
      rates = described_class.cost_rates("claude-haiku-4-5")
      expect(rates[:input]).to eq(100)
      expect(rates[:output]).to eq(500)
    end

    it "returns rates for a dated model variant (prefix match)" do
      rates = described_class.cost_rates("claude-haiku-4-5-20251201")
      expect(rates[:input]).to eq(100)
    end

    it "returns default rates for an entirely unknown model" do
      rates = described_class.cost_rates("some-unknown-model-xyz")
      expect(rates[:input]).to be_a(Integer)
      expect(rates[:output]).to be_a(Integer)
    end

    it "returns zero-cost rates for llama/mistral local model strings" do
      rates = described_class.cost_rates("llama3.2:8b")
      expect(rates[:input]).to eq(0)
      expect(rates[:output]).to eq(0)
    end
  end

  # ── Context window ───────────────────────────────────────────────────────

  describe ".context_window" do
    it "returns the context window for a known model" do
      expect(described_class.context_window("claude-haiku-4-5")).to eq(200_000)
    end

    it "returns nil for an unknown model" do
      expect(described_class.context_window("made-up-model")).to be_nil
    end

    it "handles dated variant via prefix match" do
      expect(described_class.context_window("claude-sonnet-4-6-20260101")).to eq(200_000)
    end
  end

  # ── find_with_prefix ─────────────────────────────────────────────────────

  describe ".find_with_prefix" do
    it "matches exact api_id" do
      expect(described_class.find_with_prefix("gpt-5.4")).not_to be_nil
    end

    it "matches a dated variant" do
      model = described_class.find_with_prefix("claude-sonnet-4-6-20260101")
      expect(model&.api_id).to eq("claude-sonnet-4-6")
    end

    it "returns the ollama placeholder for open-source model strings" do
      model = described_class.find_with_prefix("llama3.2:8b")
      expect(model&.api_id).to eq("ollama")

      model = described_class.find_with_prefix("mistral:7b")
      expect(model&.api_id).to eq("ollama")
    end

    it "returns nil for blank input" do
      expect(described_class.find_with_prefix(nil)).to be_nil
      expect(described_class.find_with_prefix("")).to be_nil
    end
  end

  # ── New models present ───────────────────────────────────────────────────

  describe "newly added models" do
    %w[claude-opus-4-8 claude-opus-4-7 gpt-5.5 gpt-5.5-pro].each do |api_id|
      it "includes #{api_id}" do
        expect(described_class.find(api_id)).not_to be_nil
      end
    end
  end

  # ── Deprecated models flagged ────────────────────────────────────────────

  describe "deprecated/sunset flagging" do
    it "flags claude-opus-4-6 as deprecated with a sunset date" do
      model = described_class.find("claude-opus-4-6")
      expect(model.deprecated?).to be true
      expect(model.sunset_date).to eq(Date.new(2026, 6, 15))
    end

    it "flags claude-sonnet-4-5 as deprecated" do
      model = described_class.find("claude-sonnet-4-5")
      expect(model.deprecated?).to be true
    end
  end

  # ── Constants ────────────────────────────────────────────────────────────

  describe "Anthropic constants" do
    it "defines known model ID constants" do
      expect(described_class::Anthropic::HAIKU_4_5).to eq("claude-haiku-4-5")
      expect(described_class::Anthropic::SONNET_4_6).to eq("claude-sonnet-4-6")
      expect(described_class::Anthropic::OPUS_4_8).to eq("claude-opus-4-8")
    end

    it "tier defaults point to registered models" do
      expect(described_class.find(described_class::Anthropic::DEFAULT_CHEAP)).not_to be_nil
      expect(described_class.find(described_class::Anthropic::DEFAULT_MID)).not_to be_nil
      expect(described_class.find(described_class::Anthropic::DEFAULT_TOP)).not_to be_nil
      expect(described_class.find(described_class::Anthropic::DEFAULT_SUMMARIZER)).not_to be_nil
    end
  end

  describe "OpenAI constants" do
    it "defines known model ID constants" do
      expect(described_class::OpenAI::GPT_5_4).to eq("gpt-5.4")
      expect(described_class::OpenAI::GPT_5_4_NANO).to eq("gpt-5.4-nano")
      expect(described_class::OpenAI::O4_MINI).to eq("o4-mini")
    end

    it "tier defaults point to registered models" do
      expect(described_class.find(described_class::OpenAI::DEFAULT_CHEAP)).not_to be_nil
      expect(described_class.find(described_class::OpenAI::DEFAULT_MID)).not_to be_nil
      expect(described_class.find(described_class::OpenAI::DEFAULT_TOP)).not_to be_nil
      expect(described_class.find(described_class::OpenAI::DEFAULT_SUMMARIZER)).not_to be_nil
    end
  end

  # ── .cheapest_active ─────────────────────────────────────────────────────

  describe ".cheapest_active" do
    it "returns the cheapest active anthropic model" do
      model = described_class.cheapest_active(provider: "anthropic")
      expect(model).not_to be_nil
      expect(model.active?).to be true
      expect(model.provider).to eq("anthropic")
    end

    it "filters by family when given" do
      model = described_class.cheapest_active(provider: "anthropic", family: "sonnet")
      expect(model.family).to eq("sonnet")
    end

    it "returns nil when no active models exist for provider" do
      expect(described_class.cheapest_active(provider: "nonexistent")).to be_nil
    end
  end

  # ── Integrity checks ─────────────────────────────────────────────────────

  describe "registry integrity" do
    it "every model has a non-blank api_id" do
      expect(described_class.all.map(&:api_id)).to all(be_present)
    end

    it "every model has a non-blank display_name" do
      expect(described_class.all.map(&:display_name)).to all(be_present)
    end

    it "every model has a valid status symbol" do
      valid_statuses = %i[active deprecated sunset]
      expect(described_class.all.map(&:status)).to all(be_in(valid_statuses))
    end

    it "every model has a positive context_window" do
      expect(described_class.all.map(&:context_window)).to all(be > 0)
    end

    it "every model has non-negative costs" do
      described_class.all.each do |m|
        expect(m.input_cost_per_mtok).to be >= 0
        expect(m.output_cost_per_mtok).to be >= 0
      end
    end
  end
end
