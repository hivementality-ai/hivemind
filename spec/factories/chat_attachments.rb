# frozen_string_literal: true

FactoryBot.define do
  factory :chat_attachment do
    association :session
    content_type { "image/png" }
    filename { "test_image.png" }
    byte_size { 1024 }
    sequence(:message_index) { |n| n }
  end
end
