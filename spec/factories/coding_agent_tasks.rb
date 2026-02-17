FactoryBot.define do
  factory :coding_agent_task do
    association :agent
    association :session
    task { "Add user authentication with Devise" }
    cli { "claude" }
    model { nil }
    timeout { 600 }
    status { "pending" }
    started_at { nil }
    completed_at { nil }
    sequence(:task_key) { |n| "task_#{n}" }
    process_info { {} }
    output { nil }

    trait :running do
      status { "running" }
      started_at { 5.minutes.ago }
      process_info { { pid: 12345 } }
    end

    trait :completed do
      status { "completed" }
      started_at { 10.minutes.ago }
      completed_at { 2.minutes.ago }
      output { "Task completed successfully" }
    end

    trait :failed do
      status { "failed" }
      started_at { 10.minutes.ago }
      completed_at { 2.minutes.ago }
      output { "Task failed with error" }
    end
  end
end
