# frozen_string_literal: true

require "faraday"
require "json"

module Mcp
  # MCP client for remote servers over the Streamable HTTP transport
  # (spec revision 2025-03-26). Each JSON-RPC message is POSTed to the server
  # URL; the reply is either a plain JSON body or an SSE stream carrying the
  # response. One instance owns one session: it initializes lazily and reuses
  # the +Mcp-Session-Id+ the server issues.
  class HttpClient
    PROTOCOL_VERSION = "2025-03-26"
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 60
    MAX_TOOL_PAGES = 20

    class Error < StandardError; end

    def self.discover_tools(server)
      new(server).discover_tools
    end

    def self.call_tool(server, tool_name:, arguments: {})
      new(server).call_tool(tool_name: tool_name, arguments: arguments)
    end

    def initialize(server)
      @server = server
      @session_id = nil
      @protocol_version = nil
      @next_id = 0
    end

    def discover_tools
      ensure_initialized
      tools = list_all_tools
      @server.mark_connected!(tools: tools)
      ServiceResponse.success(data: { tools: tools })
    rescue StandardError => e
      @server.mark_error!(e.message)
      ServiceResponse.failure(error: "Tool discovery failed: #{e.message}")
    end

    def call_tool(tool_name:, arguments: {})
      ensure_initialized
      result = request("tools/call", { name: tool_name, arguments: arguments })
      output = extract_content(result)
      return ServiceResponse.failure(error: "Tool call failed: #{output}") if result["isError"]

      ServiceResponse.success(data: { output: output, raw: result })
    rescue StandardError => e
      ServiceResponse.failure(error: "Tool call failed: #{e.message}")
    end

    private

    def ensure_initialized
      return if @initialized

      result = request("initialize", {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: {},
        clientInfo: { name: "hivemind", version: "1.0" }
      })
      @protocol_version = result["protocolVersion"] || PROTOCOL_VERSION
      notify("notifications/initialized")
      @initialized = true
    end

    def list_all_tools
      tools = []
      cursor = nil
      MAX_TOOL_PAGES.times do
        result = request("tools/list", cursor ? { cursor: cursor } : {})
        tools.concat(result["tools"] || [])
        cursor = result["nextCursor"]
        break if cursor.blank?
      end
      tools
    end

    def request(method, params)
      @next_id += 1
      id = @next_id
      response = post({ jsonrpc: "2.0", id: id, method: method, params: params })
      @session_id ||= response.headers["Mcp-Session-Id"].presence
      message = find_response(response, id)
      raise Error, "No response to #{method}" unless message
      raise Error, "#{message['error']['message']} (code #{message['error']['code']})" if message["error"]

      message["result"] || {}
    end

    def notify(method)
      post({ jsonrpc: "2.0", method: method })
    end

    def post(payload, retried: false)
      response = connection.post do |req|
        req.headers = request_headers
        req.body = payload.to_json
      end
      if response.status == 401 && !retried && Mcp::OAuth.refreshable?(@server)
        Mcp::OAuth.refresh!(@server)
        return post(payload, retried: true)
      end
      raise Error, "HTTP #{response.status}: #{response.body.to_s.truncate(500)}" unless response.success?

      response
    end

    def connection
      @connection ||= Faraday.new(url: @server.url, request: { open_timeout: OPEN_TIMEOUT, timeout: READ_TIMEOUT })
    end

    def request_headers
      headers = {
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream"
      }
      headers["Mcp-Session-Id"] = @session_id if @session_id
      headers["MCP-Protocol-Version"] = @protocol_version if @protocol_version
      headers.merge(Mcp::OAuth.headers_for(@server)).merge(@server.resolved_auth_headers)
    end

    def find_response(response, id)
      body = response.body.to_s
      return nil if body.strip.empty?

      sse = response.headers["Content-Type"].to_s.include?("text/event-stream")
      messages = sse ? parse_sse(body) : Array.wrap(JSON.parse(body))
      messages.find { |m| m.is_a?(Hash) && m["id"] == id && (m.key?("result") || m.key?("error")) }
    end

    def parse_sse(body)
      body.split(/\r?\n\r?\n/).filter_map do |event|
        data = event.lines.map(&:chomp).select { |l| l.start_with?("data:") }
        next if data.empty?

        JSON.parse(data.map { |l| l.delete_prefix("data:").delete_prefix(" ") }.join("\n"))
      rescue JSON::ParserError
        nil
      end
    end

    def extract_content(result)
      content = result["content"]
      return result.to_json unless content.is_a?(Array)

      content.map { |c| c["text"] || c.to_json }.join("\n")
    end
  end
end
