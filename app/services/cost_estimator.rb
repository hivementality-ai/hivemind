# frozen_string_literal: true

class CostEstimator
  # Pricing is sourced from LlmModelRegistry.
  # To update costs or add a model, edit app/models/llm_model_registry.rb.

  def self.estimate(model:, input_tokens:, output_tokens:)
    rate = LlmModelRegistry.cost_rates(model)
    ((input_tokens * rate[:input] + output_tokens * rate[:output]) / 1_000_000.0).round(4)
  end

  # Returns { input_cost_cents, output_cost_cents, total_cost_cents }
  def self.breakdown(model:, input_tokens:, output_tokens:)
    rate = LlmModelRegistry.cost_rates(model)
    input_cost  = (input_tokens  * rate[:input]  / 1_000_000.0).round(4)
    output_cost = (output_tokens * rate[:output] / 1_000_000.0).round(4)
    {
      input_cost_cents:  input_cost,
      output_cost_cents: output_cost,
      total_cost_cents:  (input_cost + output_cost).round(4)
    }
  end

  # Kept for backward compatibility — delegates to the registry.
  def self.find_rate(model)
    LlmModelRegistry.cost_rates(model)
  end
end
