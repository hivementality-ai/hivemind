# frozen_string_literal: true

FactoryBot.define do
  factory :team_chat_session do
    association :team
    association :user

    sequence(:session_key) { SecureRandom.uuid }
    status { :active }

    trait :archived do
      status { :archived }
    end

    trait :with_messages do
      after(:create) do |session|
        create_list(:team_chat_message, 5, team_chat_session: session, sender_type: 'user', sender_id: session.user.id)
      end
    end

    trait :with_agent_sessions do
      after(:create) do |session|
        agents = create_list(:agent, 3, team: session.team)
        agents.each do |agent|
          session.session_for(agent)
        end
      end
    end
  end
end
