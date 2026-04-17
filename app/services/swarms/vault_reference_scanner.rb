# frozen_string_literal: true

module Swarms
  # Scans a swarm manifest for vault: prefixed values and validates they exist.
  #
  # vault: references appear in any string field and follow the convention:
  #   "vault:namespace/key"
  #
  # This matches the existing convention used by MCP servers, API integrations,
  # and other platform models (see McpServer#resolved_env_vars).
  #
  # Workflow:
  #   1. Recursively scan the manifest Hash for any string matching vault:namespace/key.
  #   2. Collect the unique set of vault paths (namespace/key pairs).
  #   3. Query VaultEntry to verify each path exists.
  #   4. Return success when all references resolve; error with the missing list otherwise.
  #
  # Usage:
  #   result = VaultReferenceScanner.call(manifest: substituted_manifest)
  #   result.success?              # => true / false
  #   result.payload[:vault_refs]  # => ["slack/bot_token", "openai/api_key"]
  #   result.payload[:missing]     # => [] (empty on success)
  #
  # On failure (missing vault entries):
  #   result.error?               # => true
  #   result.payload[:missing]    # => ["slack/bot_token"]
  #
  # `manifest` should be a plain Ruby Hash (after VariableResolver substitution).
  class VaultReferenceScanner
    # Matches "vault:namespace/key" — namespace and key are both non-empty.
    VAULT_PATTERN = /\Avault:([^\/\s]+\/[^\s]+)\z/

    def self.call(manifest:)
      new(manifest:).call
    end

    def initialize(manifest:)
      @manifest = manifest
    end

    def call
      vault_paths = collect_vault_refs(@manifest)
      missing     = find_missing_vault_entries(vault_paths)

      if missing.any?
        return ServiceResponse.error(
          message: "Missing vault entries: #{missing.join(', ')}",
          payload: {
            vault_refs: vault_paths.sort,
            missing:    missing
          }
        )
      end

      ServiceResponse.success(
        payload: {
          vault_refs: vault_paths.sort,
          missing:    []
        }
      )
    end

    private

    attr_reader :manifest

    # Recursively collect every unique vault path found in string values.
    def collect_vault_refs(value)
      paths = Set.new

      case value
      when String
        if (match = VAULT_PATTERN.match(value))
          paths << match[1]
        end
      when Hash
        value.each_value { |v| paths.merge(collect_vault_refs(v)) }
      when Array
        value.each { |v| paths.merge(collect_vault_refs(v)) }
      end

      paths
    end

    # Check each collected vault path against the database.
    # A path "namespace/key" maps to VaultEntry namespace + key columns.
    # Returns an array of paths that have no matching VaultEntry (sorted for determinism).
    def find_missing_vault_entries(paths)
      paths.each_with_object([]) do |path, missing|
        namespace, key = path.split("/", 2)
        exists = VaultEntry.exists?(namespace: namespace, key: key)
        missing << path unless exists
      end.sort
    end
  end
end
