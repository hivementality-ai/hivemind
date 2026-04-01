FactoryBot.define do
  factory :task do
    association :team
    association :user
    sequence(:title) { |n| "Task #{n}" }
    description { nil }
    status { :todo }
    priority { :medium }
    created_by { "user" }
    position { 0 }
    metadata { {} }

    trait :backlog do
      status { :backlog }
    end

    trait :in_progress do
      status { :in_progress }
    end

    trait :review do
      status { :review }
    end

    trait :done do
      status { :done }
      completed_at { Time.current }
    end

    trait :cancelled do
      status { :cancelled }
    end

    trait :urgent do
      priority { :urgent }
    end

    trait :high do
      priority { :high }
    end

    trait :low do
      priority { :low }
    end

    trait :overdue do
      due_date { 2.days.ago }
    end

    trait :with_agent do
      association :agent
    end

    trait :with_session do
      association :session
    end

    trait :from_hashtag do
      created_by { "hashtag" }
    end
  end
end
