# frozen_string_literal: true

module Swarms
  # Validates a parsed swarm hash for cross-section consistency and size constraints.
  #
  # This runs AFTER SwarmSchema structural validation passes. It checks:
  #
  #   1. Referential integrity — all names referenced by agents actually exist
  #      in the top-level section they reference:
  #        - agent.skills[]        → names in skills[]
  #        - agent.tools[]         → names in tools[]
  #        - agent.mcp_servers[]   → names in mcp_servers[]
  #        - agent.channels[].channel_ref → refs in channels[]
  #
  #   2. Uniqueness — no duplicate names (or refs) within each top-level section:
  #        - agents[].name
  #        - skills[].name
  #        - tools[].name
  #        - channels[].ref
  #        - mcp_servers[].name
  #        - api_integrations[].name
  #
  #   3. Size limits — enforced with structured errors:
  #        - skill.summary ≤ 150 chars
  #        - skill.content ≤ 100 KB (102_400 bytes)
  #        - tool.script_template ≤ 100 KB (102_400 bytes)
  #        - total file size is handled by SwarmParser, not here
  #
  # Returns a ValidationResult (same type as SwarmSchema):
  #   valid?   – true/false
  #   errors   – array of ValidationError structs with path and message
  #
  # Usage:
  #   result = SwarmValidator.validate(raw_hash)
  #   result.valid?                      # => true / false
  #   result.errors                      # => [ValidationError, ...]
  #   result.errors.map(&:full_message)  # => ["agents[0].skills[0]: ...]
  class SwarmValidator
    SKILL_SUMMARY_MAX_CHARS  = 150
    SKILL_CONTENT_MAX_BYTES  = 100 * 1024  # 100 KB
    TOOL_SCRIPT_MAX_BYTES    = 100 * 1024  # 100 KB

    # Structured error object with path (JSON-pointer style) and message.
    ValidationError = Data.define(:path, :message) do
      def full_message = "#{path}: #{message}"
      def to_s         = full_message
    end

    ValidationResult = Data.define(:errors) do
      def valid?   = errors.empty?
      def invalid? = !valid?
    end

    def self.validate(raw)
      new.validate(raw)
    end

    def initialize
      @errors = []
      @raw    = {}.with_indifferent_access
    end

    def validate(raw)
      @errors = []

      unless raw.is_a?(Hash)
        add_error("", "swarm document must be a Hash")
        return result
      end

      @raw = raw.with_indifferent_access

      build_lookup_tables

      validate_uniqueness
      validate_referential_integrity
      validate_size_limits

      result
    end

    private

    attr_reader :raw, :errors

    # Lookup sets built from the top-level sections. Used during referential
    # integrity checks so we don't repeatedly iterate the arrays.
    attr_reader :skill_names, :tool_names, :mcp_server_names, :channel_refs

    def result
      ValidationResult.new(errors: @errors.freeze)
    end

    def add_error(path, message)
      @errors << ValidationError.new(path: path, message: message)
    end

    # ------------------------------------------------------------------
    # Lookup table construction
    # ------------------------------------------------------------------

    def build_lookup_tables
      @skill_names       = extract_names(raw[:skills],       :name)
      @tool_names        = extract_names(raw[:tools],        :name)
      @mcp_server_names  = extract_names(raw[:mcp_servers],  :name)
      @channel_refs      = extract_names(raw[:channels],     :ref)
    end

    # Returns a Set of non-blank string values for the given key across an array.
    def extract_names(array, key)
      return Set.new unless array.is_a?(Array)

      array.each_with_object(Set.new) do |item, set|
        next unless item.is_a?(Hash)

        value = item.with_indifferent_access[key]
        set << value.to_s if value.present?
      end
    end

    # ------------------------------------------------------------------
    # Uniqueness validation
    # ------------------------------------------------------------------

    def validate_uniqueness
      validate_unique_names(raw[:agents],          "agents",          :name)
      validate_unique_names(raw[:skills],          "skills",          :name)
      validate_unique_names(raw[:tools],           "tools",           :name)
      validate_unique_names(raw[:channels],        "channels",        :ref)
      validate_unique_names(raw[:mcp_servers],     "mcp_servers",     :name)
      validate_unique_names(raw[:api_integrations],"api_integrations",:name)
    end

    def validate_unique_names(array, section, key)
      return unless array.is_a?(Array)

      seen   = {}
      key_s  = key.to_s

      array.each_with_index do |item, index|
        next unless item.is_a?(Hash)

        value = item.with_indifferent_access[key]
        next if value.blank?

        identifier = value.to_s

        if seen.key?(identifier)
          add_error(
            "#{section}[#{index}].#{key_s}",
            "duplicate #{key_s} '#{identifier}' (first defined at #{section}[#{seen[identifier]}])"
          )
        else
          seen[identifier] = index
        end
      end
    end

    # ------------------------------------------------------------------
    # Referential integrity
    # ------------------------------------------------------------------

    def validate_referential_integrity
      agents = raw[:agents]
      return unless agents.is_a?(Array)

      agents.each_with_index { |agent, i| validate_agent_refs(agent, i) }
    end

    def validate_agent_refs(agent, index)
      return unless agent.is_a?(Hash)

      prefix = "agents[#{index}]"
      a      = agent.with_indifferent_access

      validate_string_refs(a[:skills],      "#{prefix}.skills",      skill_names,      "skills")
      validate_string_refs(a[:tools],       "#{prefix}.tools",       tool_names,       "tools")
      validate_string_refs(a[:mcp_servers], "#{prefix}.mcp_servers", mcp_server_names, "mcp_servers")

      validate_channel_refs(a[:channels], prefix)
    end

    # Validates an array of string names against a known Set.
    def validate_string_refs(refs, path_prefix, known_set, section_label)
      return unless refs.is_a?(Array)

      refs.each_with_index do |ref, j|
        next unless ref.is_a?(String) && ref.present?

        unless known_set.include?(ref)
          add_error(
            "#{path_prefix}[#{j}]",
            "'#{ref}' does not match any name in #{section_label}[]"
          )
        end
      end
    end

    # Validates channel bindings — each must have a channel_ref that exists in channels[].
    def validate_channel_refs(channels, agent_prefix)
      return unless channels.is_a?(Array)

      channels.each_with_index do |binding, j|
        next unless binding.is_a?(Hash)

        b   = binding.with_indifferent_access
        ref = b[:channel_ref].to_s

        next if ref.blank?

        unless channel_refs.include?(ref)
          add_error(
            "#{agent_prefix}.channels[#{j}].channel_ref",
            "'#{ref}' does not match any ref in channels[]"
          )
        end
      end
    end

    # ------------------------------------------------------------------
    # Size limits
    # ------------------------------------------------------------------

    def validate_size_limits
      validate_skill_sizes
      validate_tool_sizes
    end

    def validate_skill_sizes
      skills = raw[:skills]
      return unless skills.is_a?(Array)

      skills.each_with_index do |skill, i|
        next unless skill.is_a?(Hash)

        s      = skill.with_indifferent_access
        prefix = "skills[#{i}]"

        if s[:summary].is_a?(String) && s[:summary].length > SKILL_SUMMARY_MAX_CHARS
          add_error(
            "#{prefix}.summary",
            "exceeds #{SKILL_SUMMARY_MAX_CHARS} character limit (#{s[:summary].length} chars)"
          )
        end

        if s[:content].is_a?(String) && s[:content].bytesize > SKILL_CONTENT_MAX_BYTES
          add_error(
            "#{prefix}.content",
            "exceeds #{SKILL_CONTENT_MAX_BYTES / 1024}KB limit (#{s[:content].bytesize} bytes)"
          )
        end
      end
    end

    def validate_tool_sizes
      tools = raw[:tools]
      return unless tools.is_a?(Array)

      tools.each_with_index do |tool, i|
        next unless tool.is_a?(Hash)

        t      = tool.with_indifferent_access
        prefix = "tools[#{i}]"

        if t[:script_template].is_a?(String) && t[:script_template].bytesize > TOOL_SCRIPT_MAX_BYTES
          add_error(
            "#{prefix}.script_template",
            "exceeds #{TOOL_SCRIPT_MAX_BYTES / 1024}KB limit (#{t[:script_template].bytesize} bytes)"
          )
        end
      end
    end
  end
end
