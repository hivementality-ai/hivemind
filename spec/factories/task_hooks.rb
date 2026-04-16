# frozen_string_literal: true

FactoryBot.define do
  factory :task_hook do
    association :skill
    trigger { "post" }
    on_status { "done" }
    position { 0 }
    config { {} }
    enabled { true }

    trait :pre do
      trigger { "pre" }
    end

    trait :post do
      trigger { "post" }
    end

    trait :for_task do
      association :task
    end

    trait :for_template do
      association :task_template
    end

    trait :for_team do
      association :team
    end

    trait :without_skill do
      skill { nil }
    end
  end
end
