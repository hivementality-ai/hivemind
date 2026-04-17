# frozen_string_literal: true

module Swarms
  # Validates a parsed swarm hash for cross-section consistency.
  #
  # This runs AFTER SwarmSchema structural validation passes. It checks:
  #
  #   1. Referential integrity — all names referenced anywhere must exist in their
  #      corresponding top-level section:
  #        - agent.skills[]              → names in skills[]
  #        - agent.tools[]               → names in tools[]
  #        - agent.mcp_servers[]         → names in mcp_servers[]
  #        - agent.channels[].channel_ref → refs in channels[]
  #        - skill.tools[]               → names in tools[]
  #
  #   2. Uniqueness — no duplicate names (or refs) within each top-level section.
  #      Comparisons are case-sensitive (e.g. "Tool" and "tool" are distinct names).
  #        - agents[].name
  #        - skills[].name
  #        - tools[].name
  #        - channels[].ref
  #        - mcp_servers[].name
  #        - api_integrations[].name
  #
  # NOTE — Per-field size limits (skill.summary, skill.content, tool.script_template)
  #        are owned by SwarmSchema, not this validator.
  #        Total file size is handled by SwarmParser.
  #
  # NOTE — ValidationResult/ValidationError type contract:
  #   SwarmValidator returns a ValidationResult whose errors array contains
  #   ValidationError structs (Data objects with :path and :message fields).
  #   This differs from SwarmSchema, which returns plain Strings. SwarmParser
  #   normalises both to plain strings before surfacing errors to callers.
  #
  # Usage:
  #   result = SwarmValidator.validate(raw_hash)
  #   result.valid?                      # => true / false
  #   result.errors                      # => [ValidationError, ...]
  #   result.errors.map(&:full_message)  # => ["agents[0].skills[0]: ..."]
  class SwarmValidator
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

      result
    end

    private

    attr_reader :raw, :errors

    # Lookup sets built from the top-level sections.
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
      @skill_names      = extract_names(raw[:skills],      :name)
      @tool_names       = extract_names(raw[:tools],       :name)
      @mcp_server_names = extract_names(raw[:mcp_servers], :name)
      @channel_refs     = extract_names(raw[:channels],    :ref)
    end

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

      seen  = {}
      key_s = key.to_s

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
      agents.each_with_index { |agent, i| validate_agent_refs(agent, i) } if agents.is_a?(Array)

      skills = raw[:skills]
      skills.each_with_index { |skill, i| validate_skill_refs(skill, i) } if skills.is_a?(Array)
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

    def validate_skill_refs(skill, index)
      return unless skill.is_a?(Hash)

      s      = skill.with_indifferent_access
      prefix = "skills[#{index}]"

      validate_string_refs(s[:tools], "#{prefix}.tools", tool_names, "tools")
    end

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

  end
end
