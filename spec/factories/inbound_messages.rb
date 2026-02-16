# frozen_string_literal: true

FactoryBot.define do
  factory :inbound_message do
    association :channel
    sequence(:external_id) { |n| "ext-#{n}" }
    sender { "+15551234567" }
    content { "Hello from outside" }
    received_at { Time.current }
    metadata { {} }
  end
end
