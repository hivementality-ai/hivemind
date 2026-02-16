# frozen_string_literal: true

FactoryBot.define do
  factory :agent_template do
    sequence(:name) { |n| "Template #{n}" }
    role { "assistant" }
    category { "general" }
    version { "1.0.0" }
    description { "A test template" }
    model_config { {} }
    tools_config { {} }
    featured { false }
  end
end
