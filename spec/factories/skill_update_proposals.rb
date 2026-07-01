# frozen_string_literal: true

FactoryBot.define do
  factory :skill_update_proposal do
    association :skill
    association :proposed_by_agent, factory: :agent
    proposed_content { "# Updated Skill\n\nImproved content with better examples." }
    original_content { "# Original Skill\n\nOld content." }
    rationale        { "Added missing edge cases and improved clarity." }
    status           { "pending" }

    trait :approved do
      status { "approved" }
      reviewed_at { 1.hour.ago }
      reviewed_by_user_id { 1 }
      review_notes { "Looks good" }
    end

    trait :rejected do
      status { "rejected" }
      reviewed_at { 1.hour.ago }
      reviewed_by_user_id { 1 }
      review_notes { "Not needed" }
    end
  end
end
