FactoryBot.define do
  factory :saved_page do
    association :agent
    sequence(:title) { |n| "Weekly digest #{n}" }
    body { "# Weekly digest\n\nThree things happened." }
    source_kind { "chat" }
  end
end
