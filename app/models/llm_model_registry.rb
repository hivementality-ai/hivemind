# frozen_string_literal: true

require "date" unless defined?(Date)

# LlmModelRegistry is the single source of truth for all supported LLM model
# metadata. Add a model here and it propagates everywhere: cost estimator,
# context manager, provider dropdowns, adapter model lists.
#
# Usage:
#   LlmModelRegistry.all                          # => Array of LlmModelRegistry::Model
#   LlmModelRegistry.for_provider("anthropic")    # => Array of Model
#   LlmModelRegistry.find("claude-haiku-4-5")     # => Model or nil
#   LlmModelRegistry.active_for_provider("openai")
#
#   model.api_id                 # => "claude-haiku-4-5"
#   model.display_name           # => "Claude Haiku 4.5"
#   model.provider               # => "anthropic"
#   model.family                 # => "haiku"
#   model.context_window         # => 200_000
#   model.input_cost_per_mtok    # => 100  (cents per million tokens)
#   model.output_cost_per_mtok   # => 500
#   model.status                 # => :active | :deprecated | :sunset
#   model.sunset_date            # => Date or nil
#   model.description            # => "Fast & affordable for simple tasks"
#   model.capabilities           # => [:vision, :tool_use]
#   model.active?                # => true
#   model.deprecated?            # => false
#
module LlmModelRegistry
  # ─────────────────────────────────────────────────────────────────────────
  # Model value object
  # ─────────────────────────────────────────────────────────────────────────
  Model = Struct.new(
    :api_id,
    :display_name,
    :provider,
    :family,
    :context_window,
    :input_cost_per_mtok,
    :output_cost_per_mtok,
    :status,
    :sunset_date,
    :description,
    :capabilities,
    keyword_init: true
  ) do
    def active?
      status == :active
    end

    def deprecated?
      status == :deprecated
    end

    def sunset?
      status == :sunset
    end

    def to_select_option
      { id: api_id, name: display_name, desc: description }
    end

    def cost_rates
      { input: input_cost_per_mtok, output: output_cost_per_mtok }
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Registry definition
  # ─────────────────────────────────────────────────────────────────────────
  #
  # Costs are in cents per million tokens (USD pricing as of June 2026).
  # Sources:
  #   https://platform.claude.com/docs/en/about-claude/pricing
  #   https://platform.openai.com/docs/pricing
  #
  # Status values:
  #   :active     — fully supported, preferred
  #   :deprecated — still works, prefer newer alternatives
  #   :sunset     — end-of-life, remove support later
  #
  MODELS = [
    # ── Anthropic Claude ──────────────────────────────────────────────────

    Model.new(
      api_id:               "claude-opus-4-8",
      display_name:         "Claude Opus 4.8",
      provider:             "anthropic",
      family:               "opus",
      context_window:       200_000,
      input_cost_per_mtok:  750,
      output_cost_per_mtok: 3750,
      status:               :active,
      sunset_date:          nil,
      description:          "Most capable — frontier reasoning & code",
      capabilities:         %i[vision tool_use extended_thinking]
    ),

    Model.new(
      api_id:               "claude-opus-4-7",
      display_name:         "Claude Opus 4.7",
      provider:             "anthropic",
      family:               "opus",
      context_window:       200_000,
      input_cost_per_mtok:  650,
      output_cost_per_mtok: 3250,
      status:               :active,
      sunset_date:          nil,
      description:          "High-capability reasoning with extended thinking",
      capabilities:         %i[vision tool_use extended_thinking]
    ),

    Model.new(
      api_id:               "claude-opus-4-6",
      display_name:         "Claude Opus 4.6",
      provider:             "anthropic",
      family:               "opus",
      context_window:       200_000,
      input_cost_per_mtok:  500,
      output_cost_per_mtok: 2500,
      status:               :deprecated,
      sunset_date:          Date.new(2026, 6, 15),
      description:          "Previous Opus — complex reasoning & code (sunset June 15, 2026)",
      capabilities:         %i[vision tool_use extended_thinking]
    ),

    Model.new(
      api_id:               "claude-sonnet-4-6",
      display_name:         "Claude Sonnet 4.6",
      provider:             "anthropic",
      family:               "sonnet",
      context_window:       200_000,
      input_cost_per_mtok:  300,
      output_cost_per_mtok: 1500,
      status:               :active,
      sunset_date:          nil,
      description:          "Best balance of speed & intelligence",
      capabilities:         %i[vision tool_use]
    ),

    Model.new(
      api_id:               "claude-sonnet-4-5",
      display_name:         "Claude Sonnet 4.5",
      provider:             "anthropic",
      family:               "sonnet",
      context_window:       200_000,
      input_cost_per_mtok:  300,
      output_cost_per_mtok: 1500,
      status:               :deprecated,
      sunset_date:          Date.new(2026, 6, 15),
      description:          "Previous Sonnet — balanced speed & intelligence (sunset June 15, 2026)",
      capabilities:         %i[vision tool_use]
    ),

    Model.new(
      api_id:               "claude-haiku-4-5",
      display_name:         "Claude Haiku 4.5",
      provider:             "anthropic",
      family:               "haiku",
      context_window:       200_000,
      input_cost_per_mtok:  100,
      output_cost_per_mtok: 500,
      status:               :active,
      sunset_date:          nil,
      description:          "Fast & affordable for simple tasks",
      capabilities:         %i[vision tool_use]
    ),

    # ── OpenAI GPT ────────────────────────────────────────────────────────

    Model.new(
      api_id:               "gpt-5.5-pro",
      display_name:         "GPT-5.5 Pro",
      provider:             "openai",
      family:               "gpt",
      context_window:       1_050_000,
      input_cost_per_mtok:  5000,
      output_cost_per_mtok: 25_000,
      status:               :active,
      sunset_date:          nil,
      description:          "Most powerful GPT — frontier tasks & long context",
      capabilities:         %i[vision tool_use]
    ),

    Model.new(
      api_id:               "gpt-5.5",
      display_name:         "GPT-5.5",
      provider:             "openai",
      family:               "gpt",
      context_window:       1_050_000,
      input_cost_per_mtok:  1500,
      output_cost_per_mtok: 6000,
      status:               :active,
      sunset_date:          nil,
      description:          "Latest flagship — complex reasoning & coding",
      capabilities:         %i[vision tool_use]
    ),

    Model.new(
      api_id:               "gpt-5.4",
      display_name:         "GPT-5.4",
      provider:             "openai",
      family:               "gpt",
      context_window:       1_050_000,
      input_cost_per_mtok:  250,
      output_cost_per_mtok: 1500,
      status:               :active,
      sunset_date:          nil,
      description:          "Previous flagship — complex reasoning & coding",
      capabilities:         %i[vision tool_use]
    ),

    Model.new(
      api_id:               "gpt-5.4-pro",
      display_name:         "GPT-5.4 Pro",
      provider:             "openai",
      family:               "gpt",
      context_window:       1_050_000,
      input_cost_per_mtok:  3000,
      output_cost_per_mtok: 18_000,
      status:               :active,
      sunset_date:          nil,
      description:          "Premium GPT-5.4 tier — harder reasoning tasks",
      capabilities:         %i[vision tool_use]
    ),

    Model.new(
      api_id:               "gpt-5.4-mini",
      display_name:         "GPT-5.4 Mini",
      provider:             "openai",
      family:               "gpt",
      context_window:       400_000,
      input_cost_per_mtok:  75,
      output_cost_per_mtok: 450,
      status:               :active,
      sunset_date:          nil,
      description:          "Fast & strong for high-volume workloads",
      capabilities:         %i[vision tool_use]
    ),

    Model.new(
      api_id:               "gpt-5.4-nano",
      display_name:         "GPT-5.4 Nano",
      provider:             "openai",
      family:               "gpt",
      context_window:       400_000,
      input_cost_per_mtok:  20,
      output_cost_per_mtok: 125,
      status:               :active,
      sunset_date:          nil,
      description:          "Cheapest — classification, extraction, sub-agents",
      capabilities:         %i[vision tool_use]
    ),

    Model.new(
      api_id:               "gpt-5.3-codex",
      display_name:         "GPT-5.3 Codex",
      provider:             "openai",
      family:               "gpt",
      context_window:       400_000,
      input_cost_per_mtok:  175,
      output_cost_per_mtok: 1400,
      status:               :active,
      sunset_date:          nil,
      description:          "Best agentic coding model",
      capabilities:         %i[vision tool_use]
    ),

    Model.new(
      api_id:               "gpt-5.2",
      display_name:         "GPT-5.2",
      provider:             "openai",
      family:               "gpt",
      context_window:       400_000,
      input_cost_per_mtok:  175,
      output_cost_per_mtok: 1400,
      status:               :active,
      sunset_date:          nil,
      description:          "Previous generation flagship — coding & analysis",
      capabilities:         %i[vision tool_use]
    ),

    Model.new(
      api_id:               "gpt-5.1",
      display_name:         "GPT-5.1",
      provider:             "openai",
      family:               "gpt",
      context_window:       400_000,
      input_cost_per_mtok:  125,
      output_cost_per_mtok: 1000,
      status:               :deprecated,
      sunset_date:          nil,
      description:          "Older generation GPT-5",
      capabilities:         %i[vision tool_use]
    ),

    Model.new(
      api_id:               "gpt-5",
      display_name:         "GPT-5",
      provider:             "openai",
      family:               "gpt",
      context_window:       400_000,
      input_cost_per_mtok:  125,
      output_cost_per_mtok: 1000,
      status:               :deprecated,
      sunset_date:          nil,
      description:          "Original GPT-5",
      capabilities:         %i[vision tool_use]
    ),

    Model.new(
      api_id:               "gpt-5-mini",
      display_name:         "GPT-5 Mini",
      provider:             "openai",
      family:               "gpt",
      context_window:       400_000,
      input_cost_per_mtok:  25,
      output_cost_per_mtok: 200,
      status:               :deprecated,
      sunset_date:          nil,
      description:          "Original GPT-5 mini",
      capabilities:         %i[vision tool_use]
    ),

    Model.new(
      api_id:               "gpt-5-nano",
      display_name:         "GPT-5 Nano",
      provider:             "openai",
      family:               "gpt",
      context_window:       400_000,
      input_cost_per_mtok:  5,
      output_cost_per_mtok: 40,
      status:               :deprecated,
      sunset_date:          nil,
      description:          "Original GPT-5 nano",
      capabilities:         %i[vision tool_use]
    ),

    Model.new(
      api_id:               "gpt-4.1",
      display_name:         "GPT-4.1",
      provider:             "openai",
      family:               "gpt",
      context_window:       1_047_576,
      input_cost_per_mtok:  200,
      output_cost_per_mtok: 800,
      status:               :active,
      sunset_date:          nil,
      description:          "Great instruction following, 1M context",
      capabilities:         %i[vision tool_use]
    ),

    Model.new(
      api_id:               "gpt-4.1-mini",
      display_name:         "GPT-4.1 Mini",
      provider:             "openai",
      family:               "gpt",
      context_window:       1_047_576,
      input_cost_per_mtok:  40,
      output_cost_per_mtok: 160,
      status:               :active,
      sunset_date:          nil,
      description:          "Compact GPT-4.1 with 1M context",
      capabilities:         %i[vision tool_use]
    ),

    Model.new(
      api_id:               "gpt-4.1-nano",
      display_name:         "GPT-4.1 Nano",
      provider:             "openai",
      family:               "gpt",
      context_window:       1_047_576,
      input_cost_per_mtok:  10,
      output_cost_per_mtok: 40,
      status:               :active,
      sunset_date:          nil,
      description:          "Fastest GPT-4.1 tier",
      capabilities:         %i[vision tool_use]
    ),

    Model.new(
      api_id:               "gpt-4o",
      display_name:         "GPT-4o",
      provider:             "openai",
      family:               "gpt",
      context_window:       128_000,
      input_cost_per_mtok:  250,
      output_cost_per_mtok: 1000,
      status:               :deprecated,
      sunset_date:          nil,
      description:          "Legacy multimodal model",
      capabilities:         %i[vision tool_use]
    ),

    Model.new(
      api_id:               "gpt-4o-mini",
      display_name:         "GPT-4o Mini",
      provider:             "openai",
      family:               "gpt",
      context_window:       128_000,
      input_cost_per_mtok:  15,
      output_cost_per_mtok: 60,
      status:               :deprecated,
      sunset_date:          nil,
      description:          "Legacy compact multimodal model",
      capabilities:         %i[vision tool_use]
    ),

    # ── OpenAI Reasoning (o-series) ───────────────────────────────────────

    Model.new(
      api_id:               "o3-pro",
      display_name:         "o3-pro",
      provider:             "openai",
      family:               "o-series",
      context_window:       200_000,
      input_cost_per_mtok:  2000,
      output_cost_per_mtok: 8000,
      status:               :active,
      sunset_date:          nil,
      description:          "Extended reasoning — hard problems, more compute",
      capabilities:         %i[tool_use extended_thinking]
    ),

    Model.new(
      api_id:               "o3",
      display_name:         "o3",
      provider:             "openai",
      family:               "o-series",
      context_window:       200_000,
      input_cost_per_mtok:  200,
      output_cost_per_mtok: 800,
      status:               :active,
      sunset_date:          nil,
      description:          "Advanced reasoning — math, science, code",
      capabilities:         %i[tool_use extended_thinking]
    ),

    Model.new(
      api_id:               "o4-mini",
      display_name:         "o4-mini",
      provider:             "openai",
      family:               "o-series",
      context_window:       200_000,
      input_cost_per_mtok:  110,
      output_cost_per_mtok: 440,
      status:               :active,
      sunset_date:          nil,
      description:          "Fast reasoning for complex problems",
      capabilities:         %i[tool_use extended_thinking]
    ),

    Model.new(
      api_id:               "o3-mini",
      display_name:         "o3-mini",
      provider:             "openai",
      family:               "o-series",
      context_window:       200_000,
      input_cost_per_mtok:  110,
      output_cost_per_mtok: 440,
      status:               :deprecated,
      sunset_date:          nil,
      description:          "Older compact reasoning model",
      capabilities:         %i[tool_use extended_thinking]
    ),

    # ── Local / self-hosted ───────────────────────────────────────────────

    Model.new(
      api_id:               "ollama",
      display_name:         "Ollama (local)",
      provider:             "ollama",
      family:               "local",
      context_window:       131_072,
      input_cost_per_mtok:  0,
      output_cost_per_mtok: 0,
      status:               :active,
      sunset_date:          nil,
      description:          "Run open-source models locally",
      capabilities:         %i[tool_use]
    ),

    Model.new(
      api_id:               "openai_compatible",
      display_name:         "OpenAI Compatible",
      provider:             "openai_compatible",
      family:               "local",
      context_window:       131_072,
      input_cost_per_mtok:  0,
      output_cost_per_mtok: 0,
      status:               :active,
      sunset_date:          nil,
      description:          "Custom OpenAI-compatible endpoint",
      capabilities:         %i[tool_use]
    )
  ].freeze

  # ─────────────────────────────────────────────────────────────────────────
  # Query interface
  # ─────────────────────────────────────────────────────────────────────────

  # All registered models.
  def self.all
    MODELS
  end

  # Find a model by api_id. Returns nil when not found.
  def self.find(api_id)
    return nil if api_id.blank?
    MODELS.find { |m| m.api_id == api_id }
  end

  # Find a model by api_id, or raise KeyError.
  def self.fetch(api_id)
    find(api_id) || raise(KeyError, "LlmModelRegistry: unknown model #{api_id.inspect}")
  end

  # All models for a given provider slug ("anthropic", "openai", …).
  def self.for_provider(provider)
    MODELS.select { |m| m.provider == provider }
  end

  # Active-only models for a provider — suitable for dropdowns.
  def self.active_for_provider(provider)
    for_provider(provider).select(&:active?)
  end

  # Models not yet fully sunset — active + deprecated.
  def self.supported_for_provider(provider)
    for_provider(provider).reject(&:sunset?)
  end

  # All models that are active or deprecated (not sunset).
  def self.supported
    MODELS.reject(&:sunset?)
  end

  # Cost rates hash for a model, keyed :input / :output.
  # Falls back to a sensible default if the model is unknown.
  def self.cost_rates(api_id)
    model = find_with_prefix(api_id)
    return DEFAULT_COST_RATES if model.nil?
    model.cost_rates
  end

  # Context window for a model. Returns nil when unknown.
  def self.context_window(api_id)
    find_with_prefix(api_id)&.context_window
  end

  # Find the cheapest active model for a given provider + optional family.
  def self.cheapest_active(provider:, family: nil)
    candidates = active_for_provider(provider)
    candidates = candidates.select { |m| m.family == family } if family
    candidates.min_by(&:input_cost_per_mtok)
  end

  # Fuzzy match: exact first, then prefix (handles dated variants like
  # "claude-sonnet-4-5-20250101"), then open-source keyword fallback.
  def self.find_with_prefix(api_id)
    return nil if api_id.blank?

    exact = find(api_id)
    return exact if exact

    if api_id.match?(/llama|mistral|gemma|phi/i)
      return MODELS.find { |m| m.api_id == "ollama" }
    end

    MODELS.find { |m| api_id.start_with?(m.api_id) }
  end

  # ── Well-known model ID constants ─────────────────────────────────────
  # Reference these in application code rather than bare string literals.

  module Anthropic
    OPUS_4_8   = "claude-opus-4-8"
    OPUS_4_7   = "claude-opus-4-7"
    OPUS_4_6   = "claude-opus-4-6"
    SONNET_4_6 = "claude-sonnet-4-6"
    SONNET_4_5 = "claude-sonnet-4-5"
    HAIKU_4_5  = "claude-haiku-4-5"

    # Tier defaults — point these to the recommended model per tier.
    DEFAULT_CHEAP      = HAIKU_4_5
    DEFAULT_MID        = SONNET_4_6
    DEFAULT_TOP        = OPUS_4_8
    DEFAULT_SUMMARIZER = HAIKU_4_5
  end

  module OpenAI
    GPT_5_5_PRO   = "gpt-5.5-pro"
    GPT_5_5       = "gpt-5.5"
    GPT_5_4       = "gpt-5.4"
    GPT_5_4_PRO   = "gpt-5.4-pro"
    GPT_5_4_MINI  = "gpt-5.4-mini"
    GPT_5_4_NANO  = "gpt-5.4-nano"
    GPT_5_3_CODEX = "gpt-5.3-codex"
    GPT_5_2       = "gpt-5.2"
    GPT_4_1       = "gpt-4.1"
    GPT_4_1_MINI  = "gpt-4.1-mini"
    GPT_4_1_NANO  = "gpt-4.1-nano"
    O3_PRO        = "o3-pro"
    O3            = "o3"
    O4_MINI       = "o4-mini"

    # Tier defaults
    DEFAULT_CHEAP      = GPT_5_4_NANO
    DEFAULT_MID        = GPT_5_4_MINI
    DEFAULT_TOP        = GPT_5_4
    DEFAULT_SUMMARIZER = GPT_5_4_NANO
  end

  DEFAULT_COST_RATES = { input: 100, output: 400 }.freeze
  private_constant :DEFAULT_COST_RATES
end
