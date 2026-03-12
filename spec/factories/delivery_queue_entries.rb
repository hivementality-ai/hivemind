# frozen_string_literal: true

FactoryBot.define do
  factory :delivery_queue_entry do
    association :channel
    recipient { "+15551234567" }
    content { "Hello from the delivery queue" }
    status { "pending" }
    attempts { 0 }
    max_attempts { 5 }
    next_attempt_at { Time.current }

    trait :sent do
      status { "sent" }
      sent_at { Time.current }
      attempts { 1 }
    end

    trait :failed do
      status { "failed" }
      attempts { 2 }
      last_error { "Connection refused" }
      next_attempt_at { 5.minutes.from_now }
    end

    trait :dead_letter do
      status { "dead_letter" }
      attempts { 5 }
      last_error { "Max attempts reached" }
    end

    trait :with_agent do
      association :agent
    end

    trait :with_session do
      association :session
    end
  end
end
