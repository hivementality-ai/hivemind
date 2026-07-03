# frozen_string_literal: true

FactoryBot.define do
  factory :tool do
    sequence(:name) { |n| "tool_#{n}" }
    description { "A useful tool for the agent" }
    executor_type { "shell" }
    builtin { false }
    enabled { true }
    config { {} }
    required_credentials { [] }
    requirements { {} }
    parameters_schema do
      {
        properties: {
          command: { type: "string", description: "The command to run" }
        },
        required: [ "command" ]
      }
    end

    trait :shell_tool do
      executor_type { "shell" }
      name { "shell_command" }
    end

    trait :file_read_tool do
      executor_type { "file_read" }
      name { "read_file" }
    end

    trait :file_write_tool do
      executor_type { "file_write" }
      name { "write_file" }
    end

    trait :web_search_tool do
      executor_type { "web_search" }
      name { "search_web" }
    end

    trait :browser_tool do
      executor_type { "browser" }
      name { "browser_control" }
    end

    trait :image_tool do
      executor_type { "image" }
      name { "image_analysis" }
    end

    trait :cron_tool do
      executor_type { "cron" }
      name { "cron_scheduler" }
    end

    trait :disabled do
      enabled { false }
    end

    trait :builtin do
      builtin { true }
    end

    trait :with_agents do
      after(:create) do |tool|
        create_list(:agent, 2, agent_tools: [ build(:agent_tool, tool: tool) ])
      end
    end
  end
end
