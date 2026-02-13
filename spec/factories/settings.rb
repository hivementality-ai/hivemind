# frozen_string_literal: true

FactoryBot.define do
  factory :setting do
    sequence(:key) { |n| "setting_key_#{n}" }
    value { "default_value" }

    trait :with_string_value do
      value { "some_string_value" }
    end

    trait :with_json_value do
      value { { nested: { data: true } }.to_json }
    end

    trait :with_numeric_value do
      value { "42" }
    end

    trait :with_boolean_value do
      value { "true" }
    end
  end
end
