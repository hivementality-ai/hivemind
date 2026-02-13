FactoryBot.define do
  factory :audit_log do
    actor_type { "MyString" }
    actor_id { "MyString" }
    action { "MyString" }
    resource { "MyString" }
    metadata { "" }
  end
end
