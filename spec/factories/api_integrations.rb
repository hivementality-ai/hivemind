# frozen_string_literal: true

FactoryBot.define do
  factory :api_integration do
    sequence(:name) { |n| "integration-#{n}" }
    base_url { "https://api.example.com" }
    auth_config { {} }
    default_headers { {} }
    endpoints { [] }
    enabled { true }
  end
end
