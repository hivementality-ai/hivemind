FactoryBot.define do
  factory :api_token do
    association :user
    sequence(:name) { |n| "Token #{n}" }
    token_digest { Digest::SHA256.hexdigest("hv_#{SecureRandom.urlsafe_base64(32)}") }
    expires_at { nil }
    last_used_at { nil }
    revoked_at { nil }

    trait :expired do
      expires_at { 1.day.ago }
    end

    trait :revoked do
      revoked_at { 1.day.ago }
    end

    trait :recently_used do
      last_used_at { 5.minutes.ago }
    end

    trait :expiring_soon do
      expires_at { 1.hour.from_now }
    end
  end
end
