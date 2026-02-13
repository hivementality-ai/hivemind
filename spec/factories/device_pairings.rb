FactoryBot.define do
  factory :device_pairing do
    name { "MyString" }
    device_id { "MyString" }
    device_type { "MyString" }
    token_digest { "MyString" }
    status { 1 }
    approved_at { "2026-02-13 10:49:58" }
    metadata { "" }
  end
end
