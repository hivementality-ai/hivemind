FactoryBot.define do
  factory :team_message do
    association :from_agent, factory: :agent
    association :team
    to_agent { nil }
    content { "Hello, team!" }
    message_type { "chat" }
    metadata { {} }

    trait :direct_message do
      association :to_agent, factory: :agent
    end

    trait :broadcast do
      to_agent { nil }
    end

    trait :system_message do
      message_type { "system" }
      content { "Agent joined the team" }
    end

    trait :task_message do
      message_type { "task" }
      content { "Please help with this task" }
      metadata { { task_id: "123", priority: "high" } }
    end
  end
end
