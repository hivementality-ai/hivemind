FactoryBot.define do
  factory :session do
    session_key { "MyString" }
    agent { nil }
    title { "MyString" }
    transcript { "" }
    metadata { "" }
    input_tokens { "" }
    output_tokens { "" }
    total_tokens { "" }
    status { 1 }
    last_activity_at { "2026-02-13 10:49:52" }
  end
end
