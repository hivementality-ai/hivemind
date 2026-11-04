# frozen_string_literal: true

module Mcp
  class ToolResolver
    MAX_TOOL_NAME_LENGTH = 64

    def self.call(agent)
      new(agent).call
    end

    # @return [Array<Mcp::ToolProxy>] the agent's MCP tools, ready to join its tool list
    def self.proxies(agent)
      call(agent).data[:tools].map { |tool| ToolProxy.new(tool) }
    rescue StandardError => e
      Rails.logger.warn("[Mcp::ToolResolver] MCP tool resolution failed: #{e.message}")
      []
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
            name: llm_name("#{prefix}_#{tool['name']}"),
            description: tool["description"] || "MCP tool from #{server.name}",
            input_schema: tool["inputSchema"] || { type: "object", properties: {}, required: [] },
            _mcp: { server_id: server.id, original_tool_name: tool["name"] }
          }
        end
      end
      ServiceResponse.success(data: { tools: mcp_tools })
    end

    private

    # Model APIs only accept tool names matching [a-zA-Z0-9_-]{1,64}; one bad
    # name rejects the whole turn, so long names keep a hash suffix to stay unique.
    def llm_name(raw)
      name = raw.gsub(/[^a-zA-Z0-9_-]/, "_")
      return name if name.length <= MAX_TOOL_NAME_LENGTH

      "#{name[0, MAX_TOOL_NAME_LENGTH - 9]}_#{Digest::SHA256.hexdigest(name)[0, 8]}"
    end
  end
end
