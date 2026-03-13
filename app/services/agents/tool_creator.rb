# frozen_string_literal: true

module Agents
  class ToolCreator
    FORBIDDEN_PATTERNS = [
      /rm\s+-rf\s+\//,
      /mkfs/,
      /dd\s+if=/,
      /:(){ :\|:& };:/,
      /curl.*\|\s*bash/,
      /wget.*\|\s*bash/,
      /nc\s+-l/,
      />\s*\/etc\//,
      /chmod\s+777/,
      /sudo\s+/,
      /eval\s*\(/,
      /\/proc\//,
      /\/sys\//,
      /passwd/,
      /shadow/,
      /crontab/,
      /vault_?entry|api_?key|secret|password|token/i
    ].freeze

    MAX_SCRIPT_LENGTH = 10_000

    def self.call(agent:, name:, description:, script_template:, parameters: {}, share_with_team: false)
      new(agent:, name:, description:, script_template:, parameters:, share_with_team:).call
    end

    def initialize(agent:, name:, description:, script_template:, parameters:, share_with_team:)
      @agent = agent
      @name = name
      @description = description
      @script_template = script_template
      @parameters = parameters || {}
      @share_with_team = share_with_team
    end

    def call
      validation = validate_inputs
      return validation if validation

      scan_result = scan_script
      return ServiceResponse.failure(error: "Script blocked: #{scan_result[:reasons].join(', ')}") if scan_result[:blocked]

      tool = Tool.create!(
        name: @name,
        description: @description,
        executor_type: "custom_script",
        script_template: @script_template,
        parameters_schema: build_parameters_schema,
        enabled: false,
        builtin: false,
        config: {
          created_by_agent_id: @agent.id,
          created_by_agent_name: @agent.name,
          security_scan: scan_result,
          share_with_team: @share_with_team,
          created_at: Time.current.iso8601
        }
      )

      create_approval_request(tool, scan_result)

      warnings_text = scan_result[:warnings].any? ? " Warnings: #{scan_result[:warnings].join(', ')}" : ""
      ServiceResponse.success(data: {
        output: "Tool '#{@name}' created and submitted for approval. An admin must approve it before it can be used.#{warnings_text}",
        tool_id: tool.id,
        status: "pending_approval"
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Tool creation failed: #{e.message}")
    end

    private

    def validate_inputs
      return ServiceResponse.failure(error: "Name is required") if @name.blank?
      return ServiceResponse.failure(error: "Description is required") if @description.blank?
      return ServiceResponse.failure(error: "Script template is required") if @script_template.blank?
      return ServiceResponse.failure(error: "Script too long (max #{MAX_SCRIPT_LENGTH} chars)") if @script_template.length > MAX_SCRIPT_LENGTH
      return ServiceResponse.failure(error: "Tool '#{@name}' already exists") if Tool.exists?(name: @name)

      nil
    end

    def scan_script
      blocked = false
      reasons = []
      warnings = []

      FORBIDDEN_PATTERNS.each do |pattern|
        if @script_template.match?(pattern)
          blocked = true
          reasons << "Forbidden pattern detected: #{pattern.source.truncate(50)}"
        end
      end

      if @script_template.match?(/curl|wget|nc/) && !@script_template.match?(/https?:\/\//)
        warnings << "Script uses network tools without explicit URLs"
      end

      if @script_template.match?(/\/(?!workspace|tmp)[a-z]+\//)
        warnings << "Script references paths outside /workspace"
      end

      if @script_template.match?(/\$\{?[A-Z_]+\}?/) && !@script_template.match?(/\$\{?PATH\}?|\$\{?HOME\}?/)
        warnings << "Script accesses environment variables"
      end

      { blocked: blocked, reasons: reasons, warnings: warnings, scanned_at: Time.current.iso8601 }
    end

    def build_parameters_schema
      properties = {}
      required = []

      @parameters.each do |param_name, param_def|
        param_name = param_name.to_s
        param_def = param_def.stringify_keys if param_def.respond_to?(:stringify_keys)

        properties[param_name] = {
          "type" => param_def["type"] || "string",
          "description" => param_def["description"] || param_name.humanize
        }
        properties[param_name]["enum"] = param_def["enum"] if param_def["enum"]
        required << param_name if param_def["required"]
      end

      { "properties" => properties, "required" => required }
    end

    def create_approval_request(tool, scan_result)
      Approvals::Request.call(
        agent: @agent,
        action: "create_tool",
        resource: "Tool##{tool.id}",
        params: {
          tool_id: tool.id,
          tool_name: tool.name,
          description: tool.description,
          script_template: @script_template,
          parameters_schema: tool.parameters_schema,
          security_scan: scan_result,
          share_with_team: @share_with_team
        }
      )
    end
  end
end
