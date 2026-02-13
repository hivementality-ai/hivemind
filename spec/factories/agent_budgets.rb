FactoryBot.define do
  factory :agent_budget do
    agent { nil }
    period { "MyString" }
    limit_cents { "9.99" }
    spent_cents { "9.99" }
    reset_at { "2026-02-13 10:49:57" }
  end
end
