# frozen_string_literal: true

FactoryBot.define do
  factory :outbound_message do
    association :channel
    recipient { "+15551234567" }
    content { "Reply from agent" }
    sent_at { Time.current }
    status { "sent" }
    metadata { {} }
  end
end
