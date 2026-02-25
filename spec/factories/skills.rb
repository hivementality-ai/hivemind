# frozen_string_literal: true

FactoryBot.define do
  factory :skill do
    sequence(:name) { |n| "Skill #{n}" }
    description { "A test skill" }
    summary { "A brief test skill summary" }
    content { "# Test Skill\n\nThis is test skill content." }
    category { "utilities" }
    enabled { true }
    builtin { false }
  end
end
