# frozen_string_literal: true

module Swarms
  module Serializers
    # Converts a McpServer record into a swarm mcp_servers[] entry hash.
    #
    # Runtime-only state (status, last_connected_at, last_error, discovered_tools,
    # tools_refreshed_at, preset) is intentionally excluded — those are platform
    # lifecycle fields that don't belong in a portable swarm definition.
    #
    # Sensitive values in env_vars and auth_config are expected to be replaced
    # with vault: references by SecretStripper in the export pipeline.
    #
    # Usage:
    #   hash = McpServerSerializer.call(mcp_server: server_record)
    #   # => { "name" => "...", "transport" => "stdio", "command" => "...", ... }
    class McpServerSerializer
      def self.call(mcp_server:)
        new(mcp_server).call
      end

      def initialize(mcp_server)
        @server = mcp_server
      end

      def call
        hash = {
          "name"      => @server.name,
          "transport" => @server.transport
        }

        # Transport-specific connection fields
        hash["command"]     = @server.command     if @server.command.present?
        hash["url"]         = @server.url         if @server.url.present?
        hash["npm_package"] = @server.npm_package if @server.npm_package.present?

        # Optional configuration
        hash["icon"]        = @server.icon        if @server.icon.present?
        hash["env_vars"]    = @server.env_vars     if @server.env_vars.present?
        hash["auth_config"] = @server.auth_config  if @server.auth_config.present?
        hash["enabled"]     = @server.enabled      unless @server.enabled.nil?

        hash
      end
    end
  end
end
