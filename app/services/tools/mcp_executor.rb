# frozen_string_literal: true

module Tools
  class McpExecutor < BaseExecutor
    def call
      server_id = input["server_id"] || input.dig("_mcp", "server_id")
      tool_name = input["tool_name"] || input.dig("_mcp", "original_tool_name")
      return ServiceResponse.failure(error: "Missing server_id") unless server_id
      return ServiceResponse.failure(error: "Missing tool_name") unless tool_name
      server = McpServer.find_by(id: server_id)
      return ServiceResponse.failure(error: "MCP server not found") unless server
      return ServiceResponse.failure(error: "MCP server is not connected") unless server.connected?
      arguments = input.except("server_id", "tool_name", "_mcp")
      if server.metadata.to_h["provider"] == "pipedream"
        Mcp::PipedreamClient.call_tool(server, tool_name: tool_name, arguments: arguments)
      elsif server.stdio?
        Mcp::StdioClient.call_tool(server, tool_name: tool_name, arguments: arguments)
      else
        Mcp::SseClient.call_tool(server, tool_name: tool_name, arguments: arguments)
      end
    end
  end
end
