FactoryBot.define do
  factory :scheduled_task do
    agent { nil }
    name { "MyString" }
    schedule { "MyString" }
    job_class { "MyString" }
    params { "" }
    enabled { false }
    last_run_at { "2026-02-13 10:49:58" }
    next_run_at { "2026-02-13 10:49:58" }
  end
end
