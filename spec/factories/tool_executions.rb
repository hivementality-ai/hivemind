# frozen_string_literal: true

FactoryBot.define do
  factory :tool_execution do
    association :tool
    association :agent
    association :session

    input { { command: "ls -la" } }
    status { "running" }
    output { nil }
    error { nil }
    exit_code { nil }
    duration_ms { nil }

    trait :completed do
      status { "completed" }
      output { "file1.txt\nfile2.txt" }
      exit_code { 0 }
      duration_ms { 250 }
    end

    trait :failed do
      status { "failed" }
      error { "Command not found" }
      exit_code { 127 }
      duration_ms { 100 }
    end

    trait :running do
      status { "running" }
      duration_ms { nil }
    end
  end
end
