FactoryBot.define do
  factory :device_pairing do
    sequence(:device_id) { |n| "device_#{n}_#{SecureRandom.uuid}" }
    device_type { "mobile" }
    device_name { "iPhone" }
    status { :pending }
    metadata { {} }

    trait :pending do
      status { :pending }
      approved_at { nil }
    end

    trait :approved do
      status { :approved }
      approved_at { Time.current }
    end

    trait :rejected do
      status { :rejected }
    end

    trait :revoked do
      status { :revoked }
    end

    trait :mobile do
      device_type { "mobile" }
      device_name { "iPhone 13" }
      metadata { { platform: "ios", version: "17.0" } }
    end

    trait :desktop do
      device_type { "desktop" }
      device_name { "MacBook Pro" }
      metadata { { platform: "macos", version: "14.0" } }
    end
  end
end
