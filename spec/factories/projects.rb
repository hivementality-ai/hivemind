FactoryBot.define do
  factory :project do
    association :team
    association :user
    sequence(:title) { |n| "Project #{n}" }
    description { "A test project" }
    status { "planning" }
    priority { "normal" }
    notification_prefs { {} }
    metadata { {} }

    trait :active do
      status { "active" }
      started_at { Time.current }
    end

    trait :blocked do
      status { "blocked" }
      started_at { Time.current }
    end

    trait :completed do
      status { "completed" }
      started_at { 1.week.ago }
      completed_at { Time.current }
    end

    trait :with_lead_agent do
      lead_agent { association :agent, :with_team, team: instance.team }
    end
  end

  factory :project_milestone do
    association :project
    sequence(:title) { |n| "Milestone #{n}" }
    description { "Test milestone" }
    acceptance_criteria { "Acceptance criteria met" }
    status { "pending" }
    position { 0 }
    depends_on { [] }
    requires_approval { true }
    deliverables { [] }
    checkpoint { {} }
    retry_count { 0 }
    max_retries { 3 }
    ping_count { 0 }
    metadata { {} }
  end

  factory :project_event do
    association :project
    event_type { "project_created" }
    summary { "Test event" }
    created_at { Time.current }
  end
end
