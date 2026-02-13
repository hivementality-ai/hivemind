FactoryBot.define do
  factory :agent_budget do
    association :agent
    period { "daily" }
    limit_cents { 10000 }
    spent_cents { 0 }
    reset_at { Time.current.beginning_of_day }

    trait :daily do
      period { "daily" }
      limit_cents { 5000 }
      reset_at { Time.current.beginning_of_day }
    end

    trait :weekly do
      period { "weekly" }
      limit_cents { 25000 }
      reset_at { Time.current.beginning_of_week }
    end

    trait :monthly do
      period { "monthly" }
      limit_cents { 100000 }
      reset_at { Time.current.beginning_of_month }
    end

    trait :exceeded do
      spent_cents { 15000 }
      limit_cents { 10000 }
    end

    trait :warning do
      spent_cents { 8500 }
      limit_cents { 10000 }
    end

    trait :low_usage do
      spent_cents { 1000 }
      limit_cents { 10000 }
    end
  end
end
