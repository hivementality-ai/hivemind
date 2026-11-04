# frozen_string_literal: true

FactoryBot.define do
  factory :desktop_pairing_code do
    association :user
    device_name { "Desktop: Test-Machine" }
    code_challenge { Digest::SHA256.hexdigest("test-verifier") }

    trait :expired do
      expires_at { 1.minute.ago }
    end

    trait :used do
      used_at { 1.minute.ago }
    end
  end
end
