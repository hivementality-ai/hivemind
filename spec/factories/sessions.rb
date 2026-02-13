FactoryBot.define do
  factory :session do
    association :agent
    sequence(:session_key) { |n| "session_#{SecureRandom.uuid}_#{n}" }
    title { "Chat Session" }
    transcript { [] }
    metadata { {} }
    input_tokens { 0 }
    output_tokens { 0 }
    total_tokens { 0 }
    status { :active }
    last_activity_at { Time.current }

    trait :active do
      status { :active }
    end

    trait :completed do
      status { :completed }
    end

    trait :archived do
      status { :archived }
    end

    trait :expired do
      status { :expired }
    end

    trait :with_transcript do
      transcript do
        [
          { role: "user", content: "Hello", timestamp: 1.hour.ago.iso8601 },
          { role: "assistant", content: "Hi there!", timestamp: 1.hour.ago.iso8601 }
        ]
      end
      input_tokens { 10 }
      output_tokens { 5 }
      total_tokens { 15 }
    end
  end
end
