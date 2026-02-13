# frozen_string_literal: true

FactoryBot.define do
  factory :inbound_message do
    association :agent

    sequence(:external_message_id) { |n| "msg_#{n}_#{SecureRandom.hex(4)}" }
    source { "discord" }
    source_user_id { "user_#{SecureRandom.hex(4)}" }
    source_channel_id { "channel_#{SecureRandom.hex(4)}" }
    content { "This is a test message from external source" }
    metadata { {} }
    processed { false }
    created_at { Time.current }

    trait :discord do
      source { "discord" }
      source_user_id { "discord_#{SecureRandom.hex(4)}" }
      source_channel_id { "discord_channel_#{SecureRandom.hex(4)}" }
    end

    trait :slack do
      source { "slack" }
      source_user_id { "slack_user_#{SecureRandom.hex(4)}" }
      source_channel_id { "slack_channel_#{SecureRandom.hex(4)}" }
    end

    trait :processed do
      processed { true }
    end

    trait :with_metadata do
      metadata do
        {
          thread_id: SecureRandom.uuid,
          reaction_count: 5,
          author_name: "Test User"
        }
      end
    end
  end
end
