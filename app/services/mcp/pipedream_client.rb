# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Mcp
  # MCP client for Pipedream's remote server (https://remote.mcp.pipedream.net).
  #
  # Unlike Mcp::SseClient (a non-standard GET/POST proxy), this speaks the standard MCP
  # JSON-RPC handshake over streamable HTTP: initialize -> notifications/initialized -> tools/list
  # / tools/call. Each request carries a fresh access token plus the five Pipedream headers; the
  # app_slug and external_user_id come from the McpServer's metadata (set when the app is enabled).
  #
  # Pipedream serves either a JSON body or an SSE stream depending on the request, so responses are
  # parsed both ways.
  class PipedreamClient
    REMOTE_MCP_URL = "https://remote.mcp.pipedream.net/v3"
    PROTOCOL_VERSION = "2025-06-18"
    HTTP_TIMEOUT = 30

    def self.discover_tools(server)
      new(server).discover_tools
    end

    def self.call_tool(server, tool_name:, arguments: {})
      new(server).call_tool(tool_name: tool_name, arguments: arguments)
    end

    def initialize(server, token_manager: Pipedream::TokenManager.new)
      @server = server
      @meta = server.metadata || {}
      @tokens = token_manager
      @session_id = nil
    end

    def discover_tools
      token = require_token or return mark("Pipedream not configured or access token unavailable")

      initialize_session(token)
      result = rpc(token, "tools/list", {})
      return mark(result["error"]) if result["error"]

      tools = result.dig("result", "tools") || []
      @server.mark_connected!(tools: tools)
      ServiceResponse.success(data: { tools: tools })
    rescue StandardError => e
      mark(e.message)
    end

    def call_tool(tool_name:, arguments: {})
      token = @tokens.access_token
      return ServiceResponse.failure(error: "Pipedream not configured or access token unavailable") unless token

      initialize_session(token)
      result = rpc(token, "tools/call", { name: tool_name, arguments: arguments })
      return ServiceResponse.failure(error: error_message(result["error"])) if result["error"]

      content = result.dig("result", "content") || []
      output = content.map { |c| c["text"] || c.to_json }.join("\n")
      ServiceResponse.success(data: { output: output, raw: result["result"] })
    rescue StandardError => e
      ServiceResponse.failure(error: e.message)
    end

    private

    def require_token
      return nil unless @tokens.configured?

      @tokens.access_token
    end

    # MCP session bootstrap. Captures Mcp-Session-Id if the server is stateful; harmless when it isn't.
    def initialize_session(token)
      response = post(token, jsonrpc("initialize", {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: {},
        clientInfo: { name: "hivemind", version: "1" }
      }))
      @session_id = response["mcp-session-id"] if response.is_a?(Net::HTTPResponse)
      # notifications/initialized is a fire-and-forget notification (no id, no response expected)
      post(token, { jsonrpc: "2.0", method: "notifications/initialized", params: {} }.to_json)
    end

    def rpc(token, method, params)
      response = post(token, jsonrpc(method, params))
      raise "HTTP #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      parse_body(response)
    end

    def jsonrpc(method, params)
      { jsonrpc: "2.0", id: SecureRandom.uuid, method: method, params: params }.to_json
    end

    def post(token, body)
      uri = URI(REMOTE_MCP_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = HTTP_TIMEOUT
      http.read_timeout = HTTP_TIMEOUT

      req = Net::HTTP::Post.new(uri)
      headers(token).each { |k, v| req[k] = v }
      req.body = body
      http.request(req)
    end

    def headers(token)
      h = {
        "Authorization" => "Bearer #{token}",
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream",
        "x-pd-project-id" => @tokens.project_id.to_s,
        "x-pd-environment" => @tokens.environment.to_s,
        "x-pd-external-user-id" => @meta["external_user_id"].to_s,
        "x-pd-app-slug" => @meta["app_slug"].to_s
      }
      h["Mcp-Session-Id"] = @session_id if @session_id
      h
    end

    # Pipedream responds with either a JSON body or an SSE stream (data: {...} lines).
    def parse_body(response)
      body = response.body.to_s
      if response["content-type"].to_s.include?("text/event-stream")
        json = body.each_line.filter_map do |line|
          line = line.strip
          next unless line.start_with?("data:")

          JSON.parse(line.sub(/\Adata:\s*/, "")) rescue nil
        end.last
        json || {}
      else
        JSON.parse(body)
      end
    end

    def error_message(err)
      return err if err.is_a?(String)

      err.is_a?(Hash) ? (err["message"] || err.to_json) : err.to_s
    end

    def mark(message)
      msg = error_message(message)
      @server.mark_error!(msg)
      ServiceResponse.failure(error: msg)
    end
  end
end
