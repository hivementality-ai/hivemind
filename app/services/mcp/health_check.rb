# frozen_string_literal: true

require "open3"
require "net/http"
require "uri"

module Mcp
  class HealthCheck
    WORKSPACE_CONTAINER = "#{ENV.fetch('COMPOSE_PROJECT_NAME', 'hivemind')}-workspace-1"
    HTTP_TIMEOUT = 5

    def self.call
      new.call
    end

    def call
      results = { checked: 0, healthy: 0, unhealthy: 0 }
      McpServer.where(enabled: true, status: "connected").find_each do |server|
        results[:checked] += 1
        healthy = case server.transport
        when "stdio" then check_stdio(server)
        when "sse" then check_sse(server)
        else false
        end
        if healthy
          results[:healthy] += 1
        else
          results[:unhealthy] += 1
        end
      end
      ServiceResponse.success(data: results)
    end

    private

    def check_stdio(server)
      pid = server.metadata&.dig("pid")
      unless pid
        server.mark_error!("No PID recorded")
        return false
      end
      _, _, status = Open3.capture3("docker", "exec", WORKSPACE_CONTAINER, "kill", "-0", pid.to_s)
      unless status.success?
        server.update!(status: "disconnected", last_error: "Process #{pid} not running")
        return false
      end
      true
    rescue StandardError => e
      server.mark_error!(e.message)
      false
    end

    def check_sse(server)
      uri = URI(server.url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = HTTP_TIMEOUT
      http.read_timeout = HTTP_TIMEOUT
      response = http.head(uri.path.presence || "/")
      unless response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection)
        server.mark_error!("HTTP #{response.code}")
        return false
      end
      true
    rescue StandardError => e
      server.mark_error!(e.message)
      false
    end
  end
end
