FactoryBot.define do
  factory :channel do
    channel_type { "MyString" }
    name { "MyString" }
    config { "" }
    enabled { false }
    webhook_path { "MyString" }
  end
end
