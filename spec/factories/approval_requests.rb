FactoryBot.define do
  factory :approval_request do
    association :agent
    action { "execute_command" }
    resource { "shell_commands/ls" }
    status { "pending" }
    requested_at { Time.current }
    expires_at { 24.hours.from_now }
    trait :pending do
      status { "pending" }
      resolved_at { nil }
    end

    trait :approved do
      status { "approved" }
      resolved_at { Time.current }
    end

    trait :rejected do
      status { "rejected" }
      resolved_at { Time.current }
    end

    trait :expired do
      status { "expired" }
      expires_at { 1.hour.ago }
      resolved_at { Time.current }
    end

    trait :no_expiry do
      expires_at { nil }
    end
  end
end
