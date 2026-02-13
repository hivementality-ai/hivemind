FactoryBot.define do
  factory :provider_config do
    name { "MyString" }
    adapter_type { "MyString" }
    base_url { "MyString" }
    vault_key { "MyString" }
    model_definitions { "" }
    enabled { false }
  end
end
