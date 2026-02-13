# frozen_string_literal: true

FactoryBot.define do
  factory :sub_agent_task do
    association :parent_agent, factory: :agent
    association :child_agent, factory: :agent

    sequence(:task_key) { |n| "task-#{n}-#{SecureRandom.hex(4)}" }
    task { "Complete data analysis and report" }
    status { "pending" }
    started_at { nil }
    completed_at { nil }
    parent_session { nil }
    child_session { nil }

    trait :pending do
      status { "pending" }
      started_at { nil }
    end

    trait :running do
      status { "running" }
      started_at { 5.minutes.ago }
    end

    trait :completed do
      status { "completed" }
      started_at { 10.minutes.ago }
      completed_at { 5.minutes.ago }
    end

    trait :failed do
      status { "failed" }
      started_at { 10.minutes.ago }
      completed_at { 5.minutes.ago }
    end

    trait :with_parent_session do
      association :parent_session, factory: :session
    end

    trait :with_child_session do
      association :child_session, factory: :session
    end
  end
end
