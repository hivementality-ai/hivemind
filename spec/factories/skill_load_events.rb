# frozen_string_literal: true

FactoryBot.define do
  factory :skill_load_event do
    association :skill
    association :agent
    session { nil }
    load_tier { "manual" }
    relevance_score { nil }
    trigger_context { nil }
    was_helpful { nil }
    flagged_reason { nil }
    flagged_at { nil }
  end
end
