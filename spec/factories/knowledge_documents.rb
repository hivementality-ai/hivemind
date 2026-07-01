# frozen_string_literal: true

FactoryBot.define do
  factory :knowledge_document do
    association :agent
    sequence(:title) { |n| "Document #{n}" }
    source_type { "text" }
    status { "pending" }
    metadata { {} }
  end
end
