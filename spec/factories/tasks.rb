# frozen_string_literal: true

FactoryBot.define do
  factory :task do
    sequence(:title) { |n| "Task #{n}" }
    status   { "backlog" }
    priority { "medium" }

    trait :urgent do
      priority { "urgent" }
    end

    trait :in_progress do
      status { "in_progress" }
    end

    trait :done do
      status { "done" }
    end

    trait :overdue do
      due_at { 2.days.ago }
      status { "todo" }
    end

    trait :archived do
      status      { "done" }
      archived_at { 1.hour.ago }
    end

    trait :with_agent do
      association :created_by_agent, factory: :agent
      association :assigned_to_agent, factory: :agent
    end

    trait :with_parent do
      association :parent, factory: :task, status: "in_progress"
    end
  end
end
