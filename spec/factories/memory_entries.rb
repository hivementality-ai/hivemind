# frozen_string_literal: true

FactoryBot.define do
  factory :memory_entry do
    association :agent
    content  { "A memory about something important" }
    metadata { {} }
    category { "general" }
    status   { "active" }
  end
end
