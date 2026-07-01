# frozen_string_literal: true

FactoryBot.define do
  factory :knowledge_chunk do
    association :knowledge_document
    agent { knowledge_document.agent }
    content { "A chunk of document text about something." }
    position { 0 }
    metadata { {} }
  end
end
