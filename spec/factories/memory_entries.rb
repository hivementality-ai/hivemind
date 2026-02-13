# frozen_string_literal: true

FactoryBot.define do
  factory :memory_entry do
    association :agent

    sequence(:key) { |n| "memory_key_#{n}" }
    value { "This is a memory value" }
    memory_type { "fact" }
    importance { 5 }
    created_at { Time.current }
    updated_at { Time.current }
    last_accessed_at { Time.current }

    trait :fact do
      memory_type { "fact" }
    end

    trait :observation do
      memory_type { "observation" }
    end

    trait :preference do
      memory_type { "preference" }
    end

    trait :learned_behavior do
      memory_type { "learned_behavior" }
    end

    trait :high_importance do
      importance { 10 }
    end

    trait :low_importance do
      importance { 1 }
    end

    trait :recently_accessed do
      last_accessed_at { 1.hour.ago }
    end

    trait :not_recently_accessed do
      last_accessed_at { 30.days.ago }
    end
  end
end
