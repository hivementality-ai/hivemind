# frozen_string_literal: true

class CostEstimator
  # Rates in cents per million tokens (USD pricing as of Feb 2026)
  # Source: https://platform.claude.com/docs/en/about-claude/pricing
  #         https://platform.openai.com/docs/pricing
  RATES = {
    # Anthropic Claude
    "claude-opus-4-6"     => { input: 500,  output: 2500 },
    "claude-sonnet-4-6"   => { input: 300,  output: 1500 },
    "claude-sonnet-4-5"   => { input: 300,  output: 1500 },
    "claude-haiku-4-5"    => { input: 100,  output: 500 },

    # OpenAI GPT
    "gpt-5.2"             => { input: 175,  output: 1400 },
    "gpt-5.1"             => { input: 125,  output: 1000 },
    "gpt-5"               => { input: 125,  output: 1000 },
    "gpt-5-mini"          => { input: 25,   output: 200 },
    "gpt-5-nano"          => { input: 5,    output: 40 },
    "gpt-4.1"             => { input: 200,  output: 800 },
    "gpt-4.1-mini"        => { input: 40,   output: 160 },
    "gpt-4.1-nano"        => { input: 10,   output: 40 },
    "gpt-4o"              => { input: 250,  output: 1000 },
    "gpt-4o-mini"         => { input: 15,   output: 60 },

    # OpenAI Reasoning
    "o3"                  => { input: 200,  output: 800 },
    "o4-mini"             => { input: 110,  output: 440 },
    "o3-mini"             => { input: 110,  output: 440 },

    # Local models (free)
    "ollama"              => { input: 0, output: 0 }
  }.freeze

  DEFAULT_RATE = { input: 100, output: 400 }.freeze

  def self.estimate(model:, input_tokens:, output_tokens:)
    rate = find_rate(model)
    ((input_tokens * rate[:input] + output_tokens * rate[:output]) / 1_000_000.0).round(4)
  end

  # Returns { input_cost_cents, output_cost_cents, total_cost_cents }
  def self.breakdown(model:, input_tokens:, output_tokens:)
    rate = find_rate(model)
    input_cost = (input_tokens * rate[:input] / 1_000_000.0).round(4)
    output_cost = (output_tokens * rate[:output] / 1_000_000.0).round(4)
    { input_cost_cents: input_cost, output_cost_cents: output_cost, total_cost_cents: (input_cost + output_cost).round(4) }
  end

  def self.find_rate(model)
    # Exact match first
    return RATES[model] if RATES[model]

    # Fuzzy match for model variants (e.g. "claude-sonnet-4-5-20250101")
    RATES.each do |key, rate|
      return rate if model&.start_with?(key)
    end

    # Ollama/local models are free
    return RATES["ollama"] if model&.include?("llama") || model&.include?("mistral") || model&.include?("gemma") || model&.include?("phi")

    DEFAULT_RATE
  end
end
