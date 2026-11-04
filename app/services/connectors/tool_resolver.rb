# frozen_string_literal: true

module Connectors
  # Offers every operation of every enabled connector as a tool named
  # +connector__<slug>__<operation>+.
  class ToolResolver
    MAX_TOOL_NAME_LENGTH = 64

    # @return [Array<Connectors::ToolProxy>] connector tools, ready to join an agent's tool list
    def self.proxies(_agent = nil)
      Connector.enabled.order(:slug).flat_map do |connector|
        connector.operations.map do |operation|
          ToolProxy.new(name: tool_name(connector.slug, operation["name"]), connector: connector, operation: operation)
        end
      end
    rescue StandardError => e
      Rails.logger.warn("[Connectors::ToolResolver] connector tool resolution failed: #{e.message}")
      []
    end

    # Model APIs reject names over 64 characters, so long names keep a hash suffix to stay unique.
    #
    # @return [String] the tool name for one operation
    def self.tool_name(slug, operation)
      name = "connector__#{slug}__#{operation}"
      return name if name.length <= MAX_TOOL_NAME_LENGTH

      "#{name[0, MAX_TOOL_NAME_LENGTH - 9]}_#{Digest::SHA256.hexdigest(name)[0, 8]}"
    end
  end
end
