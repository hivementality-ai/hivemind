FactoryBot.define do
  factory :provider_config do
    sequence(:name) { |n| "Provider #{n}" }
    sequence(:adapter_type) { |n| %w[openai anthropic ollama openai_compatible][n % 4] }
    model_definitions { [] }
    vault_key { "providers/api_key" }
    enabled { true }

    trait :openai do
      name { "OpenAI" }
      adapter_type { "openai" }
      model_definitions do
        [
          { name: "gpt-4", max_tokens: 8192 },
          { name: "gpt-3.5-turbo", max_tokens: 4096 }
        ]
      end
      vault_key { "providers/openai_api_key" }
    end

    trait :anthropic do
      name { "Anthropic" }
      adapter_type { "anthropic" }
      model_definitions do
        [
          { name: "claude-3-opus-20240229", max_tokens: 4096 },
          { name: "claude-3-sonnet-20240229", max_tokens: 4096 }
        ]
      end
      vault_key { "providers/anthropic_api_key" }
    end

    trait :ollama do
      name { "Ollama" }
      adapter_type { "ollama" }
      model_definitions do
        [
          { name: "llama2", max_tokens: 2048 }
        ]
      end
      vault_key { nil }
    end

    trait :openai_compatible do
      name { "OpenAI Compatible" }
      adapter_type { "openai_compatible" }
      model_definitions do
        [
          { name: "default", max_tokens: 4096 }
        ]
      end
      vault_key { nil }
    end

    trait :disabled do
      enabled { false }
    end
  end
end
