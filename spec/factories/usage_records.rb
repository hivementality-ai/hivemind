FactoryBot.define do
  factory :usage_record do
    association :agent
    association :session, factory: :session
    provider { "openai" }
    llm_model { "gpt-4" }
    input_tokens { 100 }
    output_tokens { 50 }
    cache_tokens { 0 }
    cost_cents { 15 }
    metadata { {} }

    trait :anthropic do
      provider { "anthropic" }
      llm_model { "claude-3-opus-20240229" }
      cost_cents { 20 }
    end

    trait :ollama do
      provider { "ollama" }
      llm_model { "llama2" }
      cost_cents { 0 }
    end

    trait :expensive do
      input_tokens { 5000 }
      output_tokens { 2000 }
      cost_cents { 500 }
    end

    trait :no_session do
      session { nil }
    end
  end
end
