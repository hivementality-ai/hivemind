# frozen_string_literal: true

FactoryBot.define do
  factory :sub_agent_task do
    association :parent_agent, factory: :agent
    association :child_agent, factory: :agent
    association :parent_session, factory: :session
    association :child_session, factory: :session
    task { 'Summarize the latest quarterly report' }
    sequence(:task_key) { |n| "task_#{SecureRandom.hex(8)}_#{n}" }
    status { 'pending' }

    trait :running do
      status { 'running' }
      started_at { Time.current }
    end

    trait :completed do
      status { 'completed' }
      started_at { 1.minute.ago }
      completed_at { Time.current }
      result { 'Task completed successfully' }
    end

    trait :failed do
      status { 'failed' }
      started_at { 1.minute.ago }
      completed_at { Time.current }
      result { 'Task failed with error' }
    end
  end
end
