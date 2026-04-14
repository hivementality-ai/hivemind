# frozen_string_literal: true

FactoryBot.define do
  factory :task_template do
    sequence(:name) { |n| "Template #{n}" }
    description { "A reusable task template" }
    default_priority { "medium" }
  end
end
