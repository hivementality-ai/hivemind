# frozen_string_literal: true

module Swarms
  # Resolves {{VARIABLE_NAME}} placeholders in a swarm manifest.
  #
  # Workflow:
  #   1. Scan all string values in the manifest for {{VAR}} placeholders.
  #   2. Collect the set of unique variable names found.
  #   3. Apply defaults from the document's variables{} section.
  #   4. Validate that all required variables have a value (from defaults or overrides).
  #   5. Substitute resolved values throughout the manifest, returning a new Hash.
  #
  # Missing = blocking error. A placeholder is missing when:
  #   - It has no entry in variables{} (undeclared), OR
  #   - Its variables{} entry has required: true and no resolved value.
  # Optional placeholders (required: false) with no resolved value are left as {{VAR}} in
  # the output and do NOT block the import.
  #
  # Usage:
  #   result = VariableResolver.call(document: swarm_doc, overrides: { "API_URL" => "https://..." })
  #   result.success?           # => true / false
  #   result.payload[:manifest] # => Hash with all {{VAR}} substituted
  #   result.payload[:resolved] # => { "API_URL" => "https://..." }
  #   result.payload[:missing]  # => [] (empty on success)
  #
  # On failure (missing required variables):
  #   result.error?             # => true
  #   result.payload[:missing]  # => ["API_URL", "DB_PASSWORD"]
  #
  # The `overrides` hash represents caller-supplied values (e.g. from a user
  # prompt or an import UI form). They take precedence over variable defaults.
  class VariableResolver
    PLACEHOLDER_PATTERN = /\{\{([A-Z][A-Z0-9_]*)\}\}/

    def self.call(document:, overrides: {})
      new(document:, overrides:).call
    end

    def initialize(document:, overrides: {})
      @document  = document
      @overrides = (overrides || {}).stringify_keys
    end

    def call
      raw_manifest = document_to_hash(@document)
      placeholder_names = scan_placeholders(raw_manifest)

      resolved = build_resolved_values(placeholder_names)
      missing  = find_missing(placeholder_names, resolved)

      if missing.any?
        return ServiceResponse.error(
          message: "Missing required variables: #{missing.join(', ')}",
          payload: { missing: missing, resolved: resolved }
        )
      end

      substituted = substitute_placeholders(raw_manifest, resolved)

      ServiceResponse.success(
        payload: {
          manifest: substituted,
          resolved: resolved,
          missing:  []
        }
      )
    end

    private

    attr_reader :document, :overrides

    # Reconstruct the raw Hash from the SwarmDocument.
    # We serialize each field back so we can do a deep string scan and substitution.
    def document_to_hash(doc)
      {
        "swarm_version"    => doc.swarm_version,
        "name"             => doc.name,
        "slug"             => doc.slug,
        "description"      => doc.description,
        "version"          => doc.version,
        "license"          => doc.license,
        "tags"             => doc.tags,
        "icon"             => doc.icon,
        "homepage"         => doc.homepage,
        "author"           => author_to_hash(doc.author),
        "requires"         => requires_to_hash(doc.requires),
        "team"             => team_to_hash(doc.team),
        "agents"           => doc.agents,
        "skills"           => doc.skills,
        "tools"            => doc.tools,
        "channels"         => doc.channels,
        "mcp_servers"      => doc.mcp_servers,
        "api_integrations" => doc.api_integrations,
        "variables"        => variables_to_hash(doc.variables)
      }.compact
    end

    def author_to_hash(author)
      return nil if author.nil?

      { "name" => author.name, "url" => author.url, "email" => author.email }.compact
    end

    def requires_to_hash(requires)
      return nil if requires.nil?

      {
        "hivemind_version" => requires.hivemind_version,
        "integrations"     => requires.integrations,
        "provider_models"  => requires.provider_models
      }.compact
    end

    def team_to_hash(team)
      return nil if team.nil?

      {
        "name"        => team.name,
        "description" => team.description,
        "custom_soul" => team.custom_soul
      }.compact
    end

    def variables_to_hash(variables)
      return nil if variables.nil? || variables.empty?

      variables.transform_values do |var|
        hash = {}
        hash["description"] = var.description if var.description.present?
        # required and default are preserved even when falsy — false and nil are valid values.
        hash["required"] = var.required
        hash["type"]     = var.type if var.type.present?
        hash["default"]  = var.default unless var.default.nil?
        hash
      end
    end

    # Recursively walk any nested Hash/Array and collect all {{VAR}} names.
    def scan_placeholders(value)
      names = Set.new

      case value
      when String
        value.scan(PLACEHOLDER_PATTERN) { |m| names << m[0] }
      when Hash
        value.each_value { |v| names.merge(scan_placeholders(v)) }
      when Array
        value.each { |v| names.merge(scan_placeholders(v)) }
      end

      names
    end

    # Build the final resolved map for all placeholder names found in the manifest.
    # Priority: caller overrides > variable default > absent (not resolved)
    def build_resolved_values(names)
      names.each_with_object({}) do |name, resolved|
        if overrides.key?(name)
          resolved[name] = overrides[name].to_s
        elsif (var_def = document.variables[name]) && !var_def.default.nil?
          resolved[name] = var_def.default.to_s
        end
        # Absent key means the placeholder is unresolved — may or may not be blocking
        # depending on whether it's declared and whether it's required.
      end
    end

    # Returns the sorted list of placeholder names that block the import.
    # A placeholder is blocking when:
    #   - It is undeclared (no entry in variables{}) — we cannot safely ignore it.
    #   - Its variables{} entry has required: true and no resolved value.
    #
    # Also catches required variables declared in variables{} that never appear as
    # placeholders in content but still have no resolved value.
    def find_missing(placeholder_names, resolved)
      missing = Set.new

      placeholder_names.each do |name|
        next if resolved.key?(name)

        var_def = document.variables[name]

        if var_def.nil?
          # Undeclared placeholder — treat as missing (no basis to assume optional).
          missing << name
        elsif var_def.required
          # Declared required, no resolved value.
          missing << name
        end
        # Declared optional with no value — leave as {{VAR}} in output, not an error.
      end

      # Belt-and-suspenders: required variables declared in variables{} that were
      # never found as placeholders but still lack a value.
      document.variables.each do |name, var_def|
        next unless var_def.required
        next if resolved.key?(name)
        next if missing.include?(name)

        missing << name
      end

      missing.to_a.sort
    end

    # Recursively replace every {{VAR}} string in the manifest with its resolved value.
    # Unresolved optional placeholders are left as {{VAR}} in the output.
    def substitute_placeholders(value, resolved)
      case value
      when String
        value.gsub(PLACEHOLDER_PATTERN) { resolved[$1] || "{{#{$1}}}" }
      when Hash
        value.transform_values { |v| substitute_placeholders(v, resolved) }
      when Array
        value.map { |v| substitute_placeholders(v, resolved) }
      else
        value
      end
    end
  end
end
