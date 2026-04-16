# frozen_string_literal: true

FactoryBot.define do
  factory :task_event do
    association :task
    event_type { "status_change" }
    summary { "Status changed" }
    created_at { Time.current }
  end
end
