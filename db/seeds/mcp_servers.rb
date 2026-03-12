# frozen_string_literal: true

PRESET_MCP_SERVERS = [].freeze

PRESET_MCP_SERVERS.each do |attrs|
  server = McpServer.find_or_initialize_by(name: attrs[:name])
  server.assign_attributes(attrs.merge(preset: true, enabled: false))
  server.save!
end
