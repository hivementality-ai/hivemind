# frozen_string_literal: true

module Mcp
  # Non-persisted tool standing in for one tool on an MCP server. As a
  # SystemTool it runs through Tools::Executor without an execution row, and
  # carries the server and original tool name to Tools::McpExecutor via its config.
  class ToolProxy < SystemTool
    # @param tool [Hash] one entry from Mcp::ToolResolver
    def initialize(tool)
      super(name: tool[:name], description: tool[:description], executor_type: "mcp")
      @input_schema = tool[:input_schema]
      @server_id = tool.dig(:_mcp, :server_id)
      @original_tool_name = tool.dig(:_mcp, :original_tool_name)
    end

    def to_llm_tool
      { name: name, description: description, input_schema: @input_schema }
    end

    def effective_config
      { server_id: @server_id, tool_name: @original_tool_name }
    end
  end
end
