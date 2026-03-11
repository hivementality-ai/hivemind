# frozen_string_literal: true

FactoryBot.define do
  factory :mcp_server do
    sequence(:name) { |n| "MCP Server #{n}" }
    transport { "stdio" }
    command { "npx -y @mcp/test-server" }
    enabled { true }
    status { "disconnected" }

    trait :stdio do
      transport { "stdio" }
      command { "npx -y @mcp/test-server" }
    end

    trait :sse do
      transport { "sse" }
      command { nil }
      url { "https://mcp.example.com" }
    end

    trait :connected do
      status { "connected" }
      last_connected_at { Time.current }
    end

    trait :disconnected do
      status { "disconnected" }
    end

    trait :error do
      status { "error" }
      last_error { "Connection refused" }
    end

    trait :disabled do
      enabled { false }
    end

    trait :preset do
      preset { true }
    end

    trait :with_tools do
      discovered_tools do
        [
          { "name" => "read_file", "description" => "Read a file", "inputSchema" => { "type" => "object", "properties" => { "path" => { "type" => "string" } }, "required" => ["path"] } },
          { "name" => "list_files", "description" => "List files", "inputSchema" => { "type" => "object", "properties" => {}, "required" => [] } }
        ]
      end
      tools_refreshed_at { Time.current }
    end

    trait :with_env_vars do
      env_vars { { "API_KEY" => "test-key", "SECRET" => "vault:mcp/secret" } }
    end

    trait :with_agents do
      after(:create) do |server|
        create(:agent_mcp_server, mcp_server: server)
      end
    end
  end
end
