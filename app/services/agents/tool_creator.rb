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
    SECRET_ENV_NAME = /\A[A-Z][A-Z0-9_]*\z/

    # Creates a custom script tool pending approval.
    #
    # @param secrets [Hash{String => String}] env var name to "vault:namespace/key" reference.
    #   The script reads +$NAME+; the value is injected at run time and never passes through the agent.
    def self.call(agent:, name:, description:, script_template:, parameters: {}, share_with_team: false, secrets: {})
      new(agent:, name:, description:, script_template:, parameters:, share_with_team:, secrets:).call
    end

    def initialize(agent:, name:, description:, script_template:, parameters:, share_with_team:, secrets: {})
      @agent = agent
      @name = name
      @description = description
      @script_template = script_template
      @parameters = parameters || {}
      @share_with_team = share_with_team
      @secrets = (secrets || {}).to_h.transform_keys(&:to_s)
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
          secret_refs: @secrets,
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

      validate_secret_refs
    end

    # Secrets are passed as vault references only; a raw value or an unknown entry is refused.
    def validate_secret_refs
      @secrets.each do |env_name, reference|
        unless SECRET_ENV_NAME.match?(env_name)
          return ServiceResponse.failure(error: "Secret name '#{env_name}' must be an UPPER_SNAKE_CASE environment variable")
        end
        unless Vault::Reference.valid?(reference)
          return ServiceResponse.failure(error: "Secret #{env_name} must be a vault reference like vault:namespace/key, never the secret itself")
        end

        parts = Vault::Reference.parse(reference)
        unless VaultEntry.resolve(namespace: parts[:namespace], key: parts[:key], agent: @agent)
          return ServiceResponse.failure(error: "Vault entry #{parts[:namespace]}/#{parts[:key]} does not exist")
        end
      end

      nil
    end

    def scan_script
      blocked = false
      reasons = []
      warnings = []

      scannable = script_without_declared_secrets
      FORBIDDEN_PATTERNS.each do |pattern|
        if scannable.match?(pattern)
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

    # Declared secret variables may be named in the script; any other secret-like word stays forbidden.
    def script_without_declared_secrets
      @secrets.keys.reduce(@script_template) do |script, env_name|
        script.gsub(/\$\{#{Regexp.escape(env_name)}\}|\$#{Regexp.escape(env_name)}\b/, "")
      end
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
          secret_refs: @secrets,
          share_with_team: @share_with_team
        }
      )
    end
  end
end
