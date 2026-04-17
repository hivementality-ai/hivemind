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
    SUPPORTED_VERSIONS        = %w[1.0].freeze
    VALID_MCP_TRANSPORTS      = %w[stdio sse].freeze
    VALID_EGRESS_MODES        = %w[allowlist blocklist disabled].freeze
    VALID_CHANNEL_TYPES       = %w[slack discord telegram whatsapp signal web].freeze
    VALID_SKILL_CATEGORIES    = Skill::CATEGORIES
    VALID_VARIABLE_TYPES      = %w[string integer boolean].freeze
    VALID_THINKING_VISIBILITY = %w[hidden debug].freeze

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
      validate_top_level_metadata
      validate_requires
      validate_team
      validate_variables
      validate_agents
      validate_skills
      validate_tools
      validate_channels
      validate_mcp_servers
      validate_api_integrations

      ValidationResult.new(errors: @errors.freeze)
    end

    private

    attr_reader :raw, :errors

    # ------------------------------------------------------------------
    # Top-level fields
    # ------------------------------------------------------------------

    def validate_version
      version = raw[:swarm_version]
      if version.blank?
        errors << "swarm_version is required"
      elsif !SUPPORTED_VERSIONS.include?(version.to_s)
        errors << "swarm_version '#{version}' is not supported (supported: #{SUPPORTED_VERSIONS.join(', ')})"
      end
    end

    def validate_top_level_metadata
      errors << "name is required" if raw[:name].blank?

      if raw[:name].present? && !raw[:name].is_a?(String)
        errors << "name must be a string"
      end

      if raw[:slug].present? && !raw[:slug].is_a?(String)
        errors << "slug must be a string"
      end

      if raw[:description].present? && !raw[:description].is_a?(String)
        errors << "description must be a string"
      end

      validate_author(raw[:author]) if raw[:author].present?

      if raw[:version].present? && !raw[:version].is_a?(String)
        errors << "version must be a string"
      end

      if raw[:license].present? && !raw[:license].is_a?(String)
        errors << "license must be a string"
      end

      if raw[:tags].present? && !raw[:tags].is_a?(Array)
        errors << "tags must be an array"
      end

      if raw[:icon].present? && !raw[:icon].is_a?(String)
        errors << "icon must be a string"
      end

      if raw[:homepage].present? && !raw[:homepage].is_a?(String)
        errors << "homepage must be a string"
      end
    end

    def validate_author(author)
      unless author.is_a?(Hash)
        errors << "author must be an object"
        return
      end

      a = author.with_indifferent_access
      errors << "author.name is required" if a[:name].blank?

      if a[:name].present? && !a[:name].is_a?(String)
        errors << "author.name must be a string"
      end

      if a[:url].present? && !a[:url].is_a?(String)
        errors << "author.url must be a string"
      end

      if a[:email].present? && !a[:email].is_a?(String)
        errors << "author.email must be a string"
      end
    end

    def validate_requires
      req = raw[:requires]
      return if req.nil?

      unless req.is_a?(Hash)
        errors << "requires must be an object"
        return
      end

      r = req.with_indifferent_access

      if r[:hivemind_version].present? && !r[:hivemind_version].is_a?(String)
        errors << "requires.hivemind_version must be a string"
      end

      if r[:integrations].present?
        unless r[:integrations].is_a?(Array)
          errors << "requires.integrations must be an array"
        else
          r[:integrations].each_with_index do |item, i|
            errors << "requires.integrations[#{i}] must be a string" unless item.is_a?(String)
          end
        end
      end

      if r[:provider_models].present?
        unless r[:provider_models].is_a?(Array)
          errors << "requires.provider_models must be an array"
        else
          r[:provider_models].each_with_index do |item, i|
            errors << "requires.provider_models[#{i}] must be a string" unless item.is_a?(String)
          end
        end
      end
    end

    def validate_team
      team = raw[:team]
      return if team.nil?

      unless team.is_a?(Hash)
        errors << "team must be an object"
        return
      end

      t = team.with_indifferent_access
      errors << "team.name is required" if t[:name].blank?

      if t[:name].present? && !t[:name].is_a?(String)
        errors << "team.name must be a string"
      end

      if t[:description].present? && !t[:description].is_a?(String)
        errors << "team.description must be a string"
      end

      if t[:custom_soul].present? && !t[:custom_soul].is_a?(String)
        errors << "team.custom_soul must be a string"
      end
    end

    def validate_variables
      vars = raw[:variables]
      return if vars.nil?

      unless vars.is_a?(Hash)
        errors << "variables must be an object"
        return
      end

      vars.each do |var_name, definition|
        prefix = "variables.#{var_name}"

        unless definition.is_a?(Hash)
          errors << "#{prefix} must be an object"
          next
        end

        d = definition.with_indifferent_access
        errors << "#{prefix}.description is required" if d[:description].blank?

        if d[:required].present? && ![true, false].include?(d[:required])
          errors << "#{prefix}.required must be a boolean"
        end

        if d[:type].present? && !VALID_VARIABLE_TYPES.include?(d[:type].to_s)
          errors << "#{prefix}.type '#{d[:type]}' is invalid (must be one of: #{VALID_VARIABLE_TYPES.join(', ')})"
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

      if a[:thinking_visibility].present? && !VALID_THINKING_VISIBILITY.include?(a[:thinking_visibility].to_s)
        errors << "#{prefix}.thinking_visibility '#{a[:thinking_visibility]}' is invalid (must be one of: #{VALID_THINKING_VISIBILITY.join(', ')})"
      end

      if a[:thinking_budget_tokens].present?
        budget = a[:thinking_budget_tokens]
        unless budget.is_a?(Integer) && budget >= 1 && budget <= 128_000
          errors << "#{prefix}.thinking_budget_tokens must be an integer between 1 and 128000"
        end
      end

      validate_egress_policy(a[:egress_policy], "#{prefix}.egress_policy") if a[:egress_policy].present?

      if a[:tool_loop_config].present? && !a[:tool_loop_config].is_a?(Hash)
        errors << "#{prefix}.tool_loop_config must be an object"
      end

      if a[:model_config].present? && !a[:model_config].is_a?(Hash)
        errors << "#{prefix}.model_config must be an object"
      end

      %i[skills tools mcp_servers].each do |list_key|
        next unless a[list_key].present?

        unless a[list_key].is_a?(Array)
          errors << "#{prefix}.#{list_key} must be an array"
          next
        end

        a[list_key].each_with_index do |ref, j|
          errors << "#{prefix}.#{list_key}[#{j}] must be a string reference" unless ref.is_a?(String)
        end
      end

      validate_agent_channels(a[:channels], prefix) if a[:channels].present?
      validate_agent_scheduled_tasks(a[:scheduled_tasks], prefix) if a[:scheduled_tasks].present?
      validate_workspace_files(a[:workspace_files], prefix) if a[:workspace_files].present?
    end

    def validate_agent_channels(channels, prefix)
      unless channels.is_a?(Array)
        errors << "#{prefix}.channels must be an array"
        return
      end

      channels.each_with_index do |binding, i|
        unless binding.is_a?(Hash)
          errors << "#{prefix}.channels[#{i}] must be an object"
          next
        end

        b = binding.with_indifferent_access
        errors << "#{prefix}.channels[#{i}].channel_ref is required" if b[:channel_ref].blank?

        if b[:channel_ref].present? && !b[:channel_ref].is_a?(String)
          errors << "#{prefix}.channels[#{i}].channel_ref must be a string"
        end

        if b[:is_default].present? && ![true, false].include?(b[:is_default])
          errors << "#{prefix}.channels[#{i}].is_default must be a boolean"
        end
      end
    end

    def validate_agent_scheduled_tasks(tasks, prefix)
      unless tasks.is_a?(Array)
        errors << "#{prefix}.scheduled_tasks must be an array"
        return
      end

      tasks.each_with_index do |task, i|
        task_prefix = "#{prefix}.scheduled_tasks[#{i}]"

        unless task.is_a?(Hash)
          errors << "#{task_prefix} must be an object"
          next
        end

        t = task.with_indifferent_access
        errors << "#{task_prefix}.name is required" if t[:name].blank?
        errors << "#{task_prefix}.schedule is required" if t[:schedule].blank?

        if t[:schedule].present? && !valid_cron?(t[:schedule].to_s)
          errors << "#{task_prefix}.schedule '#{t[:schedule]}' is not a valid cron expression"
        end
      end
    end

    def validate_workspace_files(files, prefix)
      unless files.is_a?(Hash)
        errors << "#{prefix}.workspace_files must be an object"
        return
      end

      files.each do |path, content|
        if path.to_s.include?("..") || path.to_s.start_with?("/")
          errors << "#{prefix}.workspace_files key '#{path}' must be a relative path without directory traversal"
        end

        if content.is_a?(String) && content.bytesize > 1_048_576
          errors << "#{prefix}.workspace_files['#{path}'] exceeds 1MB limit"
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

        if s[:summary].present? && s[:summary].to_s.length > 150
          errors << "#{prefix}.summary exceeds 150 character limit"
        end

        if s[:content].present? && s[:content].to_s.bytesize > 100 * 1024
          errors << "#{prefix}.content exceeds 100KB limit"
        end

        if s[:category].present? && !VALID_SKILL_CATEGORIES.include?(s[:category].to_s)
          errors << "#{prefix}.category '#{s[:category]}' is invalid (must be one of: #{VALID_SKILL_CATEGORIES.join(', ')})"
        end

        if s[:tools].present?
          unless s[:tools].is_a?(Array)
            errors << "#{prefix}.tools must be an array"
          else
            s[:tools].each_with_index do |tool, j|
              errors << "#{prefix}.tools[#{j}] must be a string" unless tool.is_a?(String)
            end
          end
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
        errors << "#{prefix}.ref is required" if c[:ref].blank?
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

      if s[:auth_config].present? && !s[:auth_config].is_a?(Hash)
        errors << "#{prefix}.auth_config must be an object"
      end
    end

    def validate_api_integrations
      integrations = raw[:api_integrations]
      return if integrations.nil?

      unless integrations.is_a?(Array)
        errors << "api_integrations must be an array"
        return
      end

      integrations.each_with_index do |integration, i|
        validate_api_integration(integration, i)
      end
    end

    def validate_api_integration(integration, index)
      prefix = "api_integrations[#{index}]"

      unless integration.is_a?(Hash)
        errors << "#{prefix} must be an object"
        return
      end

      g = integration.with_indifferent_access
      errors << "#{prefix}.name is required" if g[:name].blank?
      errors << "#{prefix}.base_url is required" if g[:base_url].blank?

      if g[:auth_config].present? && !g[:auth_config].is_a?(Hash)
        errors << "#{prefix}.auth_config must be an object"
      end

      if g[:default_headers].present? && !g[:default_headers].is_a?(Hash)
        errors << "#{prefix}.default_headers must be an object"
      end

      if g[:endpoints].present?
        unless g[:endpoints].is_a?(Array)
          errors << "#{prefix}.endpoints must be an array"
        else
          g[:endpoints].each_with_index do |ep, j|
            ep_prefix = "#{prefix}.endpoints[#{j}]"
            unless ep.is_a?(Hash)
              errors << "#{ep_prefix} must be an object"
              next
            end

            ep = ep.with_indifferent_access
            errors << "#{ep_prefix}.method is required" if ep[:method].blank?
            errors << "#{ep_prefix}.path is required" if ep[:path].blank?
          end
        end
      end

      if g[:timeout_seconds].present? && (!g[:timeout_seconds].is_a?(Integer) || g[:timeout_seconds] < 1)
        errors << "#{prefix}.timeout_seconds must be a positive integer"
      end

      if g[:max_response_bytes].present? && (!g[:max_response_bytes].is_a?(Integer) || g[:max_response_bytes] < 1)
        errors << "#{prefix}.max_response_bytes must be a positive integer"
      end
    end

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    # Matches 5-part cron expressions. Supports digits, wildcards, ranges,
    # steps, and named day abbreviations (MON-FRI etc).
    # Does not validate field-level numeric ranges — that belongs in a
    # dedicated cron parser.
    CRON_PART_PATTERN = /\A(\*|(\d+|\*)([\/\-]\d+)?|
                          (MON|TUE|WED|THU|FRI|SAT|SUN)
                          (\-(MON|TUE|WED|THU|FRI|SAT|SUN))?
                         )(,((\d+|\*)([\/\-]\d+)?|
                          (MON|TUE|WED|THU|FRI|SAT|SUN)
                          (\-(MON|TUE|WED|THU|FRI|SAT|SUN))?))*\z/xi

    def valid_cron?(expression)
      parts = expression.strip.split(/\s+/)
      return false unless parts.length == 5

      parts.all? { |part| CRON_PART_PATTERN.match?(part) }
    end
  end
end
