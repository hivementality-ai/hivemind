FactoryBot.define do
  factory :agent do
    sequence(:name) { |n| "Agent #{n}" }
    role { "Assistant" }
    status { :idle }
    model_config { { model: "gpt-4", temperature: 0.7 } }
    tools_config { { enabled_tools: [] } }
    system_prompt { "You are a helpful assistant." }
    workspace_path { "/tmp/agent_workspace" }
    enabled { true }

    trait :idle do
      status { :idle }
    end

    trait :thinking do
      status { :thinking }
      current_task { "Processing user request" }
    end

    trait :executing do
      status { :executing }
      current_task { "Running command" }
    end

    trait :waiting do
      status { :waiting }
      current_task { "Awaiting approval" }
    end

    trait :error do
      status { :error }
      current_task { "Failed to process" }
    end

    trait :with_team do
      association :team
    end

    trait :disabled do
      enabled { false }
    end

    trait :with_manager do
      association :manager, factory: :agent
    end

    trait :with_title do
      title { "Senior Engineer" }
    end
  end
end
