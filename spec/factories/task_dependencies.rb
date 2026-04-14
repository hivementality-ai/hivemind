# frozen_string_literal: true

FactoryBot.define do
  factory :task_dependency do
    association :task
    association :depends_on, factory: :task
  end
end
