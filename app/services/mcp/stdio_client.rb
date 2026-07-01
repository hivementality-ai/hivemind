# frozen_string_literal: true

require "open3"
require "json"
require "shellwords"

module Mcp
  class StdioClient
    WORKSPACE_CONTAINER = "#{ENV.fetch('COMPOSE_PROJECT_NAME', 'hivemind')}-workspace-1"

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
      request = build_jsonrpc("tools/list", {})
      response = execute_jsonrpc(request)
      return ServiceResponse.failure(error: "No JSON response from server") unless response
      if response["error"]
        return ServiceResponse.failure(error: response["error"]["message"])
      end
      tools = response.dig("result", "tools") || []
      @server.mark_connected!(tools: tools)
      ServiceResponse.success(data: { tools: tools })
    rescue StandardError => e
      @server.mark_error!(e.message)
      ServiceResponse.failure(error: e.message)
    end

    def call_tool(tool_name:, arguments: {})
      request = build_jsonrpc("tools/call", { name: tool_name, arguments: arguments })
      response = execute_jsonrpc(request)
      return ServiceResponse.failure(error: "No JSON response from server") unless response
      if response["error"]
        return ServiceResponse.failure(error: response["error"]["message"])
      end
      content = response.dig("result", "content") || []
      output = content.map { |c| c["text"] || c.to_json }.join("\n")
      ServiceResponse.success(data: { output: output, raw: response["result"] })
    rescue StandardError => e
      ServiceResponse.failure(error: e.message)
    end

    private

    def build_jsonrpc(method, params)
      { jsonrpc: "2.0", id: SecureRandom.uuid, method: method, params: params }.to_json
    end

    def execute_jsonrpc(request_json)
      env_args = @server.resolved_env_vars.flat_map { |k, v| [ "--env", "#{k}=#{v}" ] }
      cmd = [ "docker", "exec", "-i", *env_args, WORKSPACE_CONTAINER, *Shellwords.shellsplit(@server.command) ]
      stdout, stderr, status = Open3.capture3(*cmd, stdin_data: request_json + "\n")
      raise "Command failed: #{stderr}" unless status.success?
      stdout.lines.each do |line|
        line = line.strip
        next if line.empty?
        begin
          return JSON.parse(line)
        rescue JSON::ParserError
          next
        end
      end
      nil
    end
  end
end
