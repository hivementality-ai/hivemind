FactoryBot.define do
  factory :vault_entry do
    namespace { "secrets" }
    sequence(:key) { |n| "api_key_#{n}" }
    encrypted_value { "secret_value_123" }
    metadata { {} }

    trait :global do
      agent { nil }
      namespace { "global" }
    end

    trait :agent_scoped do
      association :agent
      namespace { "agent" }
    end

    trait :openai_key do
      namespace { "providers" }
      key { "openai_api_key" }
      encrypted_value { "sk-test123" }
    end

    trait :anthropic_key do
      namespace { "providers" }
      key { "anthropic_api_key" }
      encrypted_value { "sk-ant-test123" }
    end
  end
end
