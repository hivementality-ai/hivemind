FactoryBot.define do
  factory :audit_log do
    actor_type { "agent" }
    sequence(:actor_id) { |n| n.to_s }
    action { "vault.read" }
    resource { nil }
    metadata { {} }

    trait :vault_read do
      action { "vault.read" }
      resource { "vault_entries/1" }
      metadata { { namespace: "secrets", key: "api_key" } }
    end

    trait :vault_write do
      action { "vault.write" }
      resource { "vault_entries/1" }
      metadata { { namespace: "secrets", key: "api_key" } }
    end

    trait :system_actor do
      actor_type { "system" }
      actor_id { "system" }
    end

    trait :user_actor do
      actor_type { "user" }
    end
  end
end
