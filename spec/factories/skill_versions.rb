# frozen_string_literal: true

FactoryBot.define do
  factory :skill_version do
    association :skill
    sequence(:version_number) { |n| n }
    content { "# Test Skill\n\nVersion content." }
    checksum { Digest::SHA256.hexdigest(content) }
    change_source { "manual" }
    change_summary { "Test version" }
  end
end
