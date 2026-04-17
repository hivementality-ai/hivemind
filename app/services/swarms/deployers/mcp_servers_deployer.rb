# frozen_string_literal: true

module Swarms
  module Deployers
    # Creates or updates McpServer records from a SwarmDocument's mcp_servers[] section.
    #
    # Each mcp_server entry in the swarm document is a plain Hash (as produced by
    # SwarmParser#normalize_array) with indifferent-access keys.
    #
    # MCP servers are matched by name. Resolution strategies are keyed by server name:
    #   :skip      – keep existing server, return it in the results
    #   :overwrite – update existing server attributes with swarm values
    #   :rename    – create new server with an auto-suffixed name
    #   (none)     – create new server (no conflict expected)
    #
    # The payload always contains a :mcp_servers array of DeployResult value objects,
    # one per server in the document, in document order.
    #
    # Usage:
    #   result = McpServersDeployer.call(document: swarm_doc, resolutions: {})
    #   result.success?             # => true / false
    #   result.payload[:mcp_servers] # => [DeployResult, ...]
    class McpServersDeployer
      # Outcome for a single deployed MCP server.
      DeployResult = Data.define(:name, :record, :action) do
        # action is one of: :created, :updated, :skipped, :renamed
      end

      def self.call(document:, resolutions: {})
        new(document, resolutions).call
      end

      def initialize(document, resolutions)
        @document    = document
        @resolutions = resolutions.with_indifferent_access
      end

      def call
        results = @document.mcp_servers.map do |server_hash|
          deploy_server(server_hash.with_indifferent_access)
        end

        ServiceResponse.success(payload: { mcp_servers: results })
      rescue ActiveRecord::RecordInvalid => e
        ServiceResponse.error(message: "Failed to deploy MCP servers: #{e.record.errors.full_messages.join(', ')}")
      rescue StandardError => e
        ServiceResponse.error(message: "Failed to deploy MCP servers: #{e.message}")
      end

      private

      def deploy_server(server_hash)
        name     = server_hash[:name].to_s
        strategy = @resolutions[name]&.to_sym
        existing = McpServer.find_by(name: name)

        if existing.nil?
          record = create_server(name, server_hash)
          DeployResult.new(name: name, record: record, action: :created)
        else
          apply_strategy(strategy, existing, name, server_hash)
        end
      end

      def create_server(name, server_hash)
        McpServer.create!(build_attributes(name, server_hash))
      end

      def apply_strategy(strategy, existing, name, server_hash)
        case strategy
        when :skip
          DeployResult.new(name: name, record: existing, action: :skipped)
        when :overwrite
          existing.update!(build_attributes(name, server_hash))
          DeployResult.new(name: name, record: existing, action: :updated)
        when :rename
          new_name = unique_name(name)
          record   = create_server(new_name, server_hash.merge(name: new_name))
          DeployResult.new(name: new_name, record: record, action: :renamed)
        else
          # No resolution provided but conflict exists — skip to be safe.
          DeployResult.new(name: name, record: existing, action: :skipped)
        end
      end

      def build_attributes(name, server_hash)
        attrs = {
          name:        name,
          transport:   server_hash[:transport].to_s,
          enabled:     server_hash.key?(:enabled) ? server_hash[:enabled] : true,
          env_vars:    (server_hash[:env_vars].presence   || {}),
          auth_config: (server_hash[:auth_config].presence || {})
        }

        attrs[:command]     = server_hash[:command].presence     if server_hash[:command].present?
        attrs[:url]         = server_hash[:url].presence         if server_hash[:url].present?
        attrs[:npm_package] = server_hash[:npm_package].presence if server_hash[:npm_package].present?
        attrs[:icon]        = server_hash[:icon].presence        if server_hash[:icon].present?

        attrs
      end

      # Appends an incrementing suffix until the name is unique.
      def unique_name(base)
        candidate = "#{base}-2"
        counter   = 2

        while McpServer.exists?(name: candidate)
          counter  += 1
          candidate = "#{base}-#{counter}"
        end

        candidate
      end
    end
  end
end
