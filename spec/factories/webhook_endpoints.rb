FactoryBot.define do
  factory :webhook_endpoint do
    sequence(:url) { |n| "https://example.com/hooks/#{n}" }
    event_types { [ "task.completed" ] }
    enabled { true }

    trait :disabled do
      enabled { false }
    end

    trait :for_agent do
      association :agent
    end

    trait :for_team do
      association :team
    end
  end
end
