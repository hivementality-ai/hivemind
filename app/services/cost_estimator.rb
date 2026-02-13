# frozen_string_literal: true

class CostEstimator
  # Rates in cents per million tokens
  RATES = {
    "claude-opus-4-6"   => { input: 1500, output: 7500 },
    "claude-sonnet-4-5" => { input: 300,  output: 1500 },
    "claude-haiku-4-5"  => { input: 80,   output: 400 },
    "gpt-5.2"           => { input: 200,  output: 800 },
    "gpt-5.2-mini"      => { input: 40,   output: 160 },
    "gpt-5.2-nano"      => { input: 10,   output: 40 },
    "o3"                => { input: 1000,  output: 4000 },
    "o4-mini"           => { input: 110,   output: 440 }
  }.freeze

  DEFAULT_RATE = { input: 100, output: 400 }.freeze

  def self.estimate(model:, input_tokens:, output_tokens:)
    rate = RATES[model] || DEFAULT_RATE
    ((input_tokens * rate[:input] + output_tokens * rate[:output]) / 1_000_000.0).round(4)
  end
end
