# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Mcp
  class SseClient
    HTTP_TIMEOUT = 10

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
      response = make_request(:get, "/tools")
      tools = JSON.parse(response.body)
      tools = tools["tools"] if tools.is_a?(Hash) && tools.key?("tools")
      @server.mark_connected!(tools: tools)
      ServiceResponse.success(data: { tools: tools })
    rescue StandardError => e
      @server.mark_error!(e.message)
      ServiceResponse.failure(error: "Tool discovery failed: #{e.message}")
    end

    def call_tool(tool_name:, arguments: {})
      body = { name: tool_name, arguments: arguments }.to_json
      response = make_request(:post, "/tools/call", body: body)
      result = JSON.parse(response.body)
      output = extract_content(result)
      ServiceResponse.success(data: { output: output, raw: result })
    rescue StandardError => e
      ServiceResponse.failure(error: "Tool call failed: #{e.message}")
    end

    private

    def make_request(method, path, body: nil)
      uri = URI(@server.url)
      full_path = File.join(uri.path.presence || "/", path)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = HTTP_TIMEOUT
      http.read_timeout = HTTP_TIMEOUT
      request = case method
      when :get then Net::HTTP::Get.new(full_path)
      when :post
        req = Net::HTTP::Post.new(full_path)
        req.body = body
        req["Content-Type"] = "application/json"
        req
      end
      @server.resolved_auth_headers.each { |k, v| request[k] = v }
      response = http.request(request)
      raise "HTTP #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)
      response
    end

    def extract_content(result)
      content = result["content"] || result["result"]&.dig("content")
      return result.to_json unless content.is_a?(Array)
      content.map { |c| c["text"] || c.to_json }.join("\n")
    end
  end
end
