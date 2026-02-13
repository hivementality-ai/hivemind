FactoryBot.define do
  factory :team_message do
    from_agent { nil }
    to_agent { nil }
    team { nil }
    content { "MyText" }
    message_type { "MyString" }
    metadata { "" }
  end
end
