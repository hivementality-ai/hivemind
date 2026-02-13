FactoryBot.define do
  factory :scheduled_task do
    association :agent
    sequence(:name) { |n| "Task #{n}" }
    schedule { "0 9 * * *" }
    job_class { "AgentTaskJob" }
    enabled { true }
    last_run_at { nil }
    next_run_at { nil }
    last_error_at { nil }

    trait :daily do
      name { "Daily Briefing" }
      schedule { "0 9 * * *" }
    end

    trait :hourly do
      name { "Hourly Check" }
      schedule { "0 * * * *" }
    end

    trait :disabled do
      enabled { false }
    end

    trait :with_recent_run do
      last_run_at { 1.hour.ago }
      next_run_at { 23.hours.from_now }
    end

    trait :with_error do
      last_error_at { 10.minutes.ago }
    end
  end
end
