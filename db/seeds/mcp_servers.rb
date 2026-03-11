# frozen_string_literal: true

PRESET_MCP_SERVERS = [
  { name: "GitHub", transport: "stdio", command: "npx -y @modelcontextprotocol/server-github", npm_package: "@modelcontextprotocol/server-github", icon: "github", env_vars: { "GITHUB_PERSONAL_ACCESS_TOKEN" => "vault:github/token" } },
  { name: "Filesystem", transport: "stdio", command: "npx -y @modelcontextprotocol/server-filesystem /workspace", npm_package: "@modelcontextprotocol/server-filesystem", icon: "folder" },
  { name: "Brave Search", transport: "stdio", command: "npx -y @modelcontextprotocol/server-brave-search", npm_package: "@modelcontextprotocol/server-brave-search", icon: "search", env_vars: { "BRAVE_API_KEY" => "" } },
  { name: "PostgreSQL", transport: "stdio", command: "npx -y @modelcontextprotocol/server-postgres postgresql://localhost/mydb", npm_package: "@modelcontextprotocol/server-postgres", icon: "database" },
  { name: "Google Drive", transport: "stdio", command: "npx -y @modelcontextprotocol/server-gdrive", npm_package: "@modelcontextprotocol/server-gdrive", icon: "cloud" },
  { name: "Slack", transport: "stdio", command: "npx -y @modelcontextprotocol/server-slack", npm_package: "@modelcontextprotocol/server-slack", icon: "message-square", env_vars: { "SLACK_BOT_TOKEN" => "", "SLACK_TEAM_ID" => "" } }
].freeze

PRESET_MCP_SERVERS.each do |attrs|
  server = McpServer.find_or_initialize_by(name: attrs[:name])
  server.assign_attributes(attrs.merge(preset: true, enabled: false))
  server.save!
end
