# frozen_string_literal: true

FactoryBot.define do
  factory :heartbeat_run do
    association :agent
    status { "ok" }
    summary { "Heartbeat completed with no action required." }
    duration_ms { 120 }
    input_tokens { 50 }
    output_tokens { 20 }
    metadata { {} }
    session { nil }

    trait :with_session do
      association :session
    end

    trait :action_taken do
      status { "action_taken" }
      summary { "Sent a message to the team channel." }
    end

    trait :error do
      status { "error" }
      summary { "Provider resolution failed." }
    end
  end
end
