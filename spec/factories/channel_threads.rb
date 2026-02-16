FactoryBot.define do
  factory :channel_thread do
    association :channel
    association :agent
    sequence(:external_thread_id) { |n| "thread_#{n}.#{Time.current.to_f}" }
    last_active_at { Time.current }
    
    trait :old do
      last_active_at { 2.hours.ago }
    end
    
    trait :recent do
      last_active_at { 5.minutes.ago }
    end
  end
end