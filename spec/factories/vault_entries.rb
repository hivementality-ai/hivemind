FactoryBot.define do
  factory :vault_entry do
    agent { nil }
    namespace { "MyString" }
    key { "MyString" }
    encrypted_value { "MyText" }
    metadata { "" }
  end
end
