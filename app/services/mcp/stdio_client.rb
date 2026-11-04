# frozen_string_literal: true

module Mcp
  # MCP client for stdio servers; requests run over the long-lived session
  # Mcp::StdioRegistry keeps for each server.
  class StdioClient
    MAX_TOOL_PAGES = 20

    def self.discover_tools(server)
      new(server).discover_tools
    end

    def self.call_tool(server, tool_name:, arguments: {})
      new(server).call_tool(tool_name: tool_name, arguments: arguments)
    end

    def initialize(server)
      @server = server
    end

    def discover_tools
      tools = Mcp::StdioRegistry.with_session(@server) { |session| list_all_tools(session) }
      @server.mark_connected!(tools: tools)
      ServiceResponse.success(data: { tools: tools })
    rescue StandardError => e
      @server.mark_error!(e.message)
      ServiceResponse.failure(error: e.message)
    end

    def call_tool(tool_name:, arguments: {})
      result = Mcp::StdioRegistry.with_session(@server) do |session|
        session.request("tools/call", { name: tool_name, arguments: arguments })
      end
      output = extract_content(result)
      return ServiceResponse.failure(error: "Tool call failed: #{output}") if result["isError"]

      ServiceResponse.success(data: { output: output, raw: result })
    rescue StandardError => e
      ServiceResponse.failure(error: e.message)
    end

    private

    def list_all_tools(session)
      tools = []
      cursor = nil
      MAX_TOOL_PAGES.times do
        result = session.request("tools/list", cursor ? { cursor: cursor } : {})
        tools.concat(result["tools"] || [])
        cursor = result["nextCursor"]
        break if cursor.blank?
      end
      tools
    end

    def extract_content(result)
      content = result["content"]
      return result.to_json unless content.is_a?(Array)

      content.map { |c| c["text"] || c.to_json }.join("\n")
    end
  end
end
