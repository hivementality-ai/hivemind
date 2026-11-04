# frozen_string_literal: true

module Connectors
  # Non-persisted tool standing in for one connector operation. As a SystemTool it
  # runs through Tools::Executor and carries the connector and operation to
  # Tools::ConnectorExecutor via its config.
  class ToolProxy < SystemTool
    EMPTY_SCHEMA = { "type" => "object", "properties" => {}, "required" => [] }.freeze

    # @param name [String] LLM-facing tool name
    # @param connector [Connector]
    # @param operation [Hash] one entry of +connector.operations+
    def initialize(name:, connector:, operation:)
      super(name: name, description: operation["description"], executor_type: "connector")
      @connector_id = connector.id
      @operation_name = operation["name"]
      @input_schema = operation["params"].presence || EMPTY_SCHEMA
    end

    def to_llm_tool
      { name: name, description: description, input_schema: @input_schema }
    end

    def effective_config
      { connector_id: @connector_id, operation: @operation_name }
    end
  end
end
