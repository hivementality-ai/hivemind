# frozen_string_literal: true

FactoryBot.define do
  factory :task_attachment do
    association :task
    sequence(:title) { |n| "Attachment #{n}" }
    url              { "https://example.com/doc-#{SecureRandom.hex(4)}.pdf" }
    content_type     { "application/pdf" }
    uploaded_by      { "test@example.com" }
  end
end
