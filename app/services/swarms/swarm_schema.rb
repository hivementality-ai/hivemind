# frozen_string_literal: true

module Swarms
  # Validates a raw parsed Hash against the .swarm.json schema.
  #
  # Returns a ValidationResult with:
  #   valid?   – true/false
  #   errors   – array of human-readable error strings
  #
  # Usage:
  #   result = SwarmSchema.validate(raw_hash)
  #   result.valid?   # => true / false
  #   result.errors   # => ["agents[0]: name is required", ...]
  class SwarmSchema
    SUPPORTED_VERSIONS       = %w[1.0].freeze
    VALID_AGENT_STATUSES     = %w[idle thinking executing waiting error].freeze
    VALID_MCP_TRANSPORTS     = %w[stdio sse].freeze
    VALID_EGRESS_MODES       = %w[allowlist blocklist disabled].freeze
    VALID_CHANNEL_TYPES      = %w[slack discord telegram whatsapp signal].freeze
    VALID_SKILL_CATEGORIES   = Skill::CATEGORIES
    VALID_TASK_CONF_STATUSES = %w[active pending disabled paused].freeze

    ValidationResult = Data.define(:errors) do
      def valid? = errors.empty?
      def invalid? = !valid?
    end

    # Validate a raw Hash (already JSON-parsed). Does NOT raise — always returns
    # a ValidationResult.
    def self.validate(raw)
      new(raw).validate
    end

    def initialize(raw)
      @raw    = raw.with_indifferent_access
      @errors = []
    end

    def validate
      validate_version
      validate_metadata
      validate_variables
      validate_vault_refs
      validate_agents
      validate_skills
      validate_tools
      validate_channels
      validate_mcp_servers
      validate_scheduled_tasks

      ValidationResult.new(errors: @errors.freeze)
    end

    private

    attr_reader :raw, :errors

    # ------------------------------------------------------------------
    # Top-level sections
    # ------------------------------------------------------------------

    def validate_version
      version = raw[:swarm_version]
      if version.blank?
        errors << "swarm_version is required"
      elsif !SUPPORTED_VERSIONS.include?(version.to_s)
        errors << "swarm_version '#{version}' is not supported (supported: #{SUPPORTED_VERSIONS.join(', ')})"
      end
    end

    def validate_metadata
      meta = raw[:metadata]
      if meta.nil?
        errors << "metadata is required"
        return
      end

      unless meta.is_a?(Hash)
        errors << "metadata must be an object"
        return
      end

      meta = meta.with_indifferent_access
      errors << "metadata.name is required" if meta[:name].blank?
      errors << "metadata.name must be a string" if meta[:name].present? && !meta[:name].is_a?(String)

      if meta[:tags].present? && !meta[:tags].is_a?(Array)
        errors << "metadata.tags must be an array"
      end
    end

    def validate_variables
      vars = raw[:variables]
      return if vars.nil?

      unless vars.is_a?(Array)
        errors << "variables must be an array"
        return
      end

      vars.each_with_index do |var, i|
        prefix = "variables[#{i}]"
        unless var.is_a?(Hash)
          errors << "#{prefix} must be an object"
          next
        end

        v = var.with_indifferent_access
        errors << "#{prefix}.name is required" if v[:name].blank?
        errors << "#{prefix}.name must be a string" if v[:name].present? && !v[:name].is_a?(String)

        if v[:required].present? && ![true, false].include?(v[:required])
          errors << "#{prefix}.required must be a boolean"
        end
      end
    end

    def validate_vault_refs
      refs = raw[:vault_refs]
      return if refs.nil?

      unless refs.is_a?(Array)
        errors << "vault_refs must be an array"
        return
      end

      refs.each_with_index do |ref, i|
        prefix = "vault_refs[#{i}]"
        unless ref.is_a?(Hash)
          errors << "#{prefix} must be an object"
          next
        end

        r = ref.with_indifferent_access
        errors << "#{prefix}.path is required" if r[:path].blank?

        if r[:path].present? && !r[:path].to_s.include?("/")
          errors << "#{prefix}.path must be in 'namespace/key' format (got '#{r[:path]}')"
        end
      end
    end

    def validate_agents
      agents = raw[:agents]
      return if agents.nil?

      unless agents.is_a?(Array)
        errors << "agents must be an array"
        return
      end

      agents.each_with_index do |agent, i|
        validate_agent(agent, i)
      end
    end

    def validate_agent(agent, index)
      prefix = "agents[#{index}]"

      unless agent.is_a?(Hash)
        errors << "#{prefix} must be an object"
        return
      end

      a = agent.with_indifferent_access

      errors << "#{prefix}.name is required" if a[:name].blank?
      errors << "#{prefix}.role is required" if a[:role].blank?

      if a[:egress_policy].present?
        validate_egress_policy(a[:egress_policy], "#{prefix}.egress_policy")
      end

      if a[:tool_loop_config].present? && !a[:tool_loop_config].is_a?(Hash)
        errors << "#{prefix}.tool_loop_config must be an object"
      end

      if a[:model_config].present? && !a[:model_config].is_a?(Hash)
        errors << "#{prefix}.model_config must be an object"
      end

      %i[skills tools mcp_servers channels].each do |list_key|
        next unless a[list_key].present?

        unless a[list_key].is_a?(Array)
          errors << "#{prefix}.#{list_key} must be an array of strings"
          next
        end

        a[list_key].each_with_index do |ref, j|
          unless ref.is_a?(String)
            errors << "#{prefix}.#{list_key}[#{j}] must be a string reference"
          end
        end
      end
    end

    def validate_egress_policy(policy, prefix)
      unless policy.is_a?(Hash)
        errors << "#{prefix} must be an object"
        return
      end

      p = policy.with_indifferent_access
      mode = p[:mode]

      if mode.present? && !VALID_EGRESS_MODES.include?(mode.to_s)
        errors << "#{prefix}.mode '#{mode}' is invalid (must be one of: #{VALID_EGRESS_MODES.join(', ')})"
      end

      if p[:rules].present?
        unless p[:rules].is_a?(Array)
          errors << "#{prefix}.rules must be an array"
          return
        end

        p[:rules].each_with_index do |rule, i|
          unless rule.is_a?(Hash) && rule.with_indifferent_access[:pattern].present?
            errors << "#{prefix}.rules[#{i}] must have a 'pattern' field"
          end
        end
      end
    end

    def validate_skills
      skills = raw[:skills]
      return if skills.nil?

      unless skills.is_a?(Array)
        errors << "skills must be an array"
        return
      end

      skills.each_with_index do |skill, i|
        prefix = "skills[#{i}]"

        unless skill.is_a?(Hash)
          errors << "#{prefix} must be an object"
          next
        end

        s = skill.with_indifferent_access
        errors << "#{prefix}.name is required" if s[:name].blank?
        errors << "#{prefix}.content is required" if s[:content].blank?
        errors << "#{prefix}.summary is required" if s[:summary].blank?

        if s[:category].present? && !VALID_SKILL_CATEGORIES.include?(s[:category].to_s)
          errors << "#{prefix}.category '#{s[:category]}' is invalid (must be one of: #{VALID_SKILL_CATEGORIES.join(', ')})"
        end
      end
    end

    def validate_tools
      tools = raw[:tools]
      return if tools.nil?

      unless tools.is_a?(Array)
        errors << "tools must be an array"
        return
      end

      tools.each_with_index do |tool, i|
        prefix = "tools[#{i}]"

        unless tool.is_a?(Hash)
          errors << "#{prefix} must be an object"
          next
        end

        t = tool.with_indifferent_access
        errors << "#{prefix}.name is required" if t[:name].blank?
        errors << "#{prefix}.description is required" if t[:description].blank?
        errors << "#{prefix}.executor_type is required" if t[:executor_type].blank?

        if t[:executor_type] == "custom_script" && t[:script_template].blank?
          errors << "#{prefix}.script_template is required when executor_type is 'custom_script'"
        end
      end
    end

    def validate_channels
      channels = raw[:channels]
      return if channels.nil?

      unless channels.is_a?(Array)
        errors << "channels must be an array"
        return
      end

      channels.each_with_index do |channel, i|
        prefix = "channels[#{i}]"

        unless channel.is_a?(Hash)
          errors << "#{prefix} must be an object"
          next
        end

        c = channel.with_indifferent_access
        errors << "#{prefix}.name is required" if c[:name].blank?

        if c[:channel_type].blank?
          errors << "#{prefix}.channel_type is required"
        elsif !VALID_CHANNEL_TYPES.include?(c[:channel_type].to_s)
          errors << "#{prefix}.channel_type '#{c[:channel_type]}' is invalid (must be one of: #{VALID_CHANNEL_TYPES.join(', ')})"
        end
      end
    end

    def validate_mcp_servers
      servers = raw[:mcp_servers]
      return if servers.nil?

      unless servers.is_a?(Array)
        errors << "mcp_servers must be an array"
        return
      end

      servers.each_with_index do |server, i|
        validate_mcp_server(server, i)
      end
    end

    def validate_mcp_server(server, index)
      prefix = "mcp_servers[#{index}]"

      unless server.is_a?(Hash)
        errors << "#{prefix} must be an object"
        return
      end

      s = server.with_indifferent_access
      errors << "#{prefix}.name is required" if s[:name].blank?

      transport = s[:transport].to_s
      if transport.blank?
        errors << "#{prefix}.transport is required"
      elsif !VALID_MCP_TRANSPORTS.include?(transport)
        errors << "#{prefix}.transport '#{transport}' is invalid (must be one of: #{VALID_MCP_TRANSPORTS.join(', ')})"
      else
        case transport
        when "stdio"
          errors << "#{prefix}.command is required for stdio transport" if s[:command].blank?
        when "sse"
          errors << "#{prefix}.url is required for sse transport" if s[:url].blank?
        end
      end

      if s[:env_vars].present? && !s[:env_vars].is_a?(Hash)
        errors << "#{prefix}.env_vars must be an object"
      end
    end

    def validate_scheduled_tasks
      tasks = raw[:scheduled_tasks]
      return if tasks.nil?

      unless tasks.is_a?(Array)
        errors << "scheduled_tasks must be an array"
        return
      end

      tasks.each_with_index do |task, i|
        prefix = "scheduled_tasks[#{i}]"

        unless task.is_a?(Hash)
          errors << "#{prefix} must be an object"
          next
        end

        t = task.with_indifferent_access
        errors << "#{prefix}.name is required" if t[:name].blank?
        errors << "#{prefix}.schedule is required" if t[:schedule].blank?
        errors << "#{prefix}.agent is required" if t[:agent].blank?

        if t[:schedule].present? && !valid_cron?(t[:schedule].to_s)
          errors << "#{prefix}.schedule '#{t[:schedule]}' is not a valid cron expression"
        end

        if t[:confirmation_status].present? && !VALID_TASK_CONF_STATUSES.include?(t[:confirmation_status].to_s)
          errors << "#{prefix}.confirmation_status '#{t[:confirmation_status]}' is invalid (must be one of: #{VALID_TASK_CONF_STATUSES.join(', ')})"
        end
      end
    end

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    CRON_PART_PATTERN = /\A[\d\*,\-\/]+\z/

    def valid_cron?(expression)
      parts = expression.strip.split(/\s+/)
      return false unless parts.length == 5

      parts.all? { |part| CRON_PART_PATTERN.match?(part) }
    end
  end
end
