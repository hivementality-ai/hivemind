# frozen_string_literal: true

FactoryBot.define do
  factory :team_chat_message do
    association :team_chat_session
    target_agent { nil }

    sequence(:sender_id) { |n| n }
    sender_type { "user" }
    content { "This is a test message" }

    trait :from_user do
      sender_type { "user" }
    end

    trait :from_agent do
      sender_type { "agent" }
      association :target_agent, factory: :agent
    end

    trait :with_mention do
      after(:create) do |message|
        agent = create(:agent, team: message.team_chat_session.team)
        message.update(content: "Hey @#{agent.name}, can you help?", target_agent: agent)
      end
    end

    trait :team_broadcast do
      content { "@team I need help from everyone" }
    end
  end
end
