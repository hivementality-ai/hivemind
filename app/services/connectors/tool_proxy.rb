# frozen_string_literal: true

module Connectors
  # Non-persisted tool standing in for one connector operation. As a SystemTool it
  # runs through Tools::Executor and carries the connector and operation to
  # Tools::ConnectorExecutor via its config.
  class ToolProxy < SystemTool
    # @return [String] display name of the connector, searched by find_tools
    attr_reader :connector_name

    # @return [Integer] id of the connector this operation belongs to
    attr_reader :connector_id

    # @return [String] operation name
    attr_reader :operation_name

    # @return [String] HTTP method of the operation
    attr_reader :http_method

    # @return [String] path template of the operation
    attr_reader :path

    READ_METHODS = %w[GET HEAD].freeze

    EMPTY_SCHEMA = { "type" => "object", "properties" => {}, "required" => [] }.freeze

    # @param name [String] LLM-facing tool name
    # @param connector [Connector]
    # @param operation [Hash] one entry of +connector.operations+
    def initialize(name:, connector:, operation:)
      super(name: name, description: operation["description"], executor_type: "connector")
      @connector_id = connector.id
      @connector_name = connector.name
      @operation_name = operation["name"]
      @http_method = operation["method"].to_s.upcase
      @path = operation["path"].to_s
      @read_only = operation["read_only"]
      @input_schema = operation["params"].presence || EMPTY_SCHEMA
    end

    def to_llm_tool
      { name: name, description: description, input_schema: @input_schema }
    end

    # An explicit +read_only+ flag on the operation wins; otherwise GET and HEAD are read-only.
    #
    # @return [Boolean] true when running the operation changes nothing in the other app
    def read_only?
      [ true, false ].include?(@read_only) ? @read_only : READ_METHODS.include?(@http_method)
    end

    def effective_config
      { connector_id: @connector_id, operation: @operation_name }
    end
  end
end
