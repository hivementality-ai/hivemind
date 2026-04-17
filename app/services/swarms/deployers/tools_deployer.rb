# frozen_string_literal: true

module Swarms
  module Deployers
    # Creates or updates Tool records from a SwarmDocument's tools[] section.
    #
    # Swarm tools are always custom_script executor tools. Each tool entry is a
    # plain Hash (as produced by SwarmParser#normalize_array) with the following
    # relevant fields:
    #   name              – required
    #   description       – optional
    #   script_template   – optional bash script body
    #   parameters        – optional Hash of parameter definitions
    #   share_with_team   – optional boolean (stored in config)
    #
    # Resolution strategies are keyed by tool name:
    #   :skip      – keep existing tool, return it in results
    #   :overwrite – update existing tool attributes with swarm values
    #   :rename    – create new tool with an auto-suffixed name
    #   (none)     – create new tool (no conflict expected)
    #
    # Usage:
    #   result = ToolsDeployer.call(document: swarm_doc, resolutions: {})
    #   result.success?        # => true / false
    #   result.payload[:tools] # => [DeployResult, ...]
    class ToolsDeployer
      EXECUTOR_TYPE = "custom_script"

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
        results = @document.tools.map.with_index do |tool_hash, index|
          deploy_tool(tool_hash.with_indifferent_access, index)
        end

        ServiceResponse.success(payload: { tools: results })
      rescue ActiveRecord::RecordInvalid => e
        ServiceResponse.error(message: "Failed to deploy tools: #{e.record.errors.full_messages.join(', ')}")
      rescue StandardError => e
        ServiceResponse.error(message: "Failed to deploy tools: #{e.message}")
      end

      private

      def deploy_tool(tool_hash, _index)
        name     = tool_hash[:name].to_s
        strategy = @resolutions[name]&.to_sym
        existing = Tool.find_by(name: name)

        if existing.nil?
          record = create_tool(name, tool_hash)
          DeployResult.new(name: name, record: record, action: :created)
        else
          apply_strategy(strategy, existing, name, tool_hash)
        end
      end

      def create_tool(name, tool_hash)
        Tool.create!(build_attributes(name, tool_hash))
      end

      def apply_strategy(strategy, existing, name, tool_hash)
        case strategy
        when :skip
          DeployResult.new(name: name, record: existing, action: :skipped)
        when :overwrite
          existing.update!(build_attributes(name, tool_hash))
          DeployResult.new(name: name, record: existing, action: :updated)
        when :rename
          new_name = unique_name(name)
          record   = create_tool(new_name, tool_hash.merge(name: new_name))
          DeployResult.new(name: new_name, record: record, action: :renamed)
        else
          # No resolution provided but conflict exists — skip to be safe.
          DeployResult.new(name: name, record: existing, action: :skipped)
        end
      end

      def build_attributes(name, tool_hash)
        {
          name:              name,
          description:       tool_hash[:description].presence || name,
          executor_type:     EXECUTOR_TYPE,
          script_template:   tool_hash[:script_template].presence || "# TODO: implement script",
          parameters_schema: build_parameters_schema(tool_hash[:parameters]),
          enabled:           tool_hash.key?(:enabled) ? tool_hash[:enabled] : true,
          builtin:           false,
          config:            build_config(tool_hash)
        }
      end

      # Converts a swarm parameters Hash into the JSON schema format Tool expects.
      # Swarm format: { "param_name" => { "type" => "string", "description" => "...", "required" => true } }
      def build_parameters_schema(parameters)
        return {} if parameters.blank? || !parameters.is_a?(Hash)

        params  = parameters.with_indifferent_access
        props   = {}
        required = []

        params.each do |param_name, definition|
          next unless definition.is_a?(Hash)

          defn = definition.with_indifferent_access
          props[param_name.to_s] = {
            "type"        => defn[:type].presence || "string",
            "description" => defn[:description].presence || param_name.to_s
          }.compact

          required << param_name.to_s if defn[:required]
        end

        schema = { "properties" => props }
        schema["required"] = required if required.any?
        schema
      end

      def build_config(tool_hash)
        config = {}
        config["share_with_team"] = tool_hash[:share_with_team] if tool_hash.key?(:share_with_team)
        config
      end

      # Appends an incrementing suffix until the name is unique.
      def unique_name(base)
        candidate = "#{base}-2"
        counter   = 2

        while Tool.exists?(name: candidate)
          counter  += 1
          candidate = "#{base}-#{counter}"
        end

        candidate
      end
    end
  end
end
