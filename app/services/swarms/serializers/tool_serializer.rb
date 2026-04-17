# frozen_string_literal: true

module Swarms
  module Serializers
    # Converts a Tool record into a swarm tools[] entry hash.
    #
    # Only custom (non-builtin) tools are serialized with full content.
    # Builtin tools are referenced by name only — they are platform-provided
    # and do not need content embedded in the swarm file.
    #
    # Custom tool format:
    #   name             – tool name
    #   description      – tool description
    #   script_template  – bash script body (custom_script executor only)
    #   parameters       – Hash of parameter definitions (swarm format)
    #
    # Usage:
    #   hash = ToolSerializer.call(tool: tool_record)
    #   # custom tool => { "name" => "...", "description" => "...", "script_template" => "...", "parameters" => {...} }
    #   # builtin tool => { "name" => "..." }
    class ToolSerializer
      def self.call(tool:)
        new(tool).call
      end

      def initialize(tool)
        @tool = tool
      end

      def call
        if @tool.builtin?
          serialize_builtin
        else
          serialize_custom
        end
      end

      private

      def serialize_builtin
        { "name" => @tool.name }
      end

      def serialize_custom
        hash = {
          "name"        => @tool.name,
          "description" => @tool.description
        }

        hash["script_template"] = @tool.script_template if @tool.script_template.present?

        params = serialize_parameters(@tool.parameters_schema)
        hash["parameters"] = params if params.present?

        hash
      end

      # Converts the JSON schema parameters_schema format back into the swarm
      # parameters format:
      #   { "param_name" => { "type" => "string", "description" => "...", "required" => true } }
      #
      # This is the inverse of ToolsDeployer#build_parameters_schema.
      def serialize_parameters(schema)
        return {} if schema.blank? || !schema.is_a?(Hash)

        props    = (schema["properties"] || schema[:properties] || {}).with_indifferent_access
        required = Array(schema["required"] || schema[:required])

        return {} if props.empty?

        props.each_with_object({}) do |(param_name, definition), result|
          defn = definition.is_a?(Hash) ? definition.with_indifferent_access : {}
          entry = {}
          entry["type"]        = defn[:type].presence        || "string"
          entry["description"] = defn[:description].presence || param_name.to_s
          entry["required"]    = required.include?(param_name.to_s)
          result[param_name.to_s] = entry
        end
      end
    end
  end
end
