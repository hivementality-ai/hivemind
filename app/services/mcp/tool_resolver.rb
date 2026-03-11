# frozen_string_literal: true

module Mcp
  class ToolResolver
    def self.call(agent)
      new(agent).call
    end

    def initialize(agent)
      @agent = agent
    end

    def call
      mcp_tools = []
      @agent.mcp_servers.where(enabled: true, status: "connected").find_each do |server|
        (server.discovered_tools || []).each do |tool|
          prefix = "mcp_#{server.name.parameterize(separator: '_')}"
          mcp_tools << {
            name: "#{prefix}_#{tool['name']}",
            description: tool["description"] || "MCP tool from #{server.name}",
            input_schema: tool["inputSchema"] || { type: "object", properties: {}, required: [] },
            _mcp: { server_id: server.id, original_tool_name: tool["name"] }
          }
        end
      end
      ServiceResponse.success(data: { tools: mcp_tools })
    end
  end
end
