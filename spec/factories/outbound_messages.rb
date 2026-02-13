# frozen_string_literal: true

FactoryBot.define do
  factory :outbound_message do
    association :agent

    sequence(:external_message_id) { |n| "out_#{n}_#{SecureRandom.hex(4)}" }
    target { "discord:#{SecureRandom.hex(4)}" }
    content { "This is a response from the agent" }
    status { "pending" }
    metadata { {} }
    sent_at { nil }

    trait :sent do
      status { "sent" }
      sent_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      metadata { { error: "Channel not found" } }
    end

    trait :discord_target do
      target { "discord:#{SecureRandom.hex(4)}" }
    end

    trait :slack_target do
      target { "slack:#{SecureRandom.hex(4)}" }
    end

    trait :with_metadata do
      metadata do
        {
          thread_id: SecureRandom.uuid,
          reply_to: "msg_123",
          formatting: "markdown"
        }
      end
    end
  end
end
