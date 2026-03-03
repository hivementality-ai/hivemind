FactoryBot.define do
  factory :research_session do
    association :agent
    association :session
    query { "What are the latest advances in quantum computing?" }
    status { "queued" }
    depth { "standard" }
    focus { "general" }
    output_format { "report" }
    current_phase { nil }
    sources_count { 0 }
    sources { [] }
    findings { [] }
    progress_log { [] }
    report { nil }
    error_message { nil }
    started_at { nil }
    completed_at { nil }
    sequence(:task_key) { |n| "research_#{n}" }

    trait :running do
      status { "running" }
      started_at { 5.minutes.ago }
      current_phase { "search" }
    end

    trait :completed do
      status { "completed" }
      started_at { 10.minutes.ago }
      completed_at { 2.minutes.ago }
      current_phase { "synthesize" }
      sources_count { 5 }
      report { "# Research Report\n\nThis is the completed research report." }
    end

    trait :failed do
      status { "failed" }
      started_at { 10.minutes.ago }
      completed_at { 2.minutes.ago }
      error_message { "LLM provider resolution failed" }
    end

    trait :cancelled do
      status { "cancelled" }
      started_at { 10.minutes.ago }
      completed_at { 2.minutes.ago }
    end
  end
end
