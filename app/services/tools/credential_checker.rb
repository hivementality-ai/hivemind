# frozen_string_literal: true

module Tools
  # Checks if a tool's required credentials are present in the vault.
  # Supports multi-provider credential sets — tool is ready if ANY ONE
  # provider set is fully configured.
  #
  # Schema supports two formats:
  #
  # 1. Multi-provider (recommended):
  #    [
  #      {"provider": "twilio", "credentials": [{"namespace": "twilio", "key": "auth_token", ...}]},
  #      {"provider": "telnyx", "credentials": [{"namespace": "telnyx", "key": "api_key", ...}]}
  #    ]
  #    Tool is ready if ANY provider set has ALL credentials configured.
  #
  # 2. Flat list (legacy/single-provider):
  #    [{"namespace": "jira", "key": "api_token", ...}]
  #    Tool is ready if ALL credentials exist.
  #
  class CredentialChecker
    # Check if at least one provider set is fully configured
    # @param tool [Tool] The tool to check
    # @return [Boolean] true if ready (or no credentials required)
    def self.ready?(tool)
      return true if tool.required_credentials.blank?

      provider_sets = normalize_provider_sets(tool.required_credentials)
      provider_sets.any? { |ps| provider_set_ready?(ps) }
    end

    # List which providers are fully configured
    # @param tool [Tool] The tool to check
    # @return [Array<String>] Provider names that are ready
    def self.available_providers(tool)
      return [] if tool.required_credentials.blank?

      provider_sets = normalize_provider_sets(tool.required_credentials)
      provider_sets.select { |ps| provider_set_ready?(ps) }
                   .map { |ps| ps["provider"] }
    end

    # List which providers are NOT fully configured and what's missing
    # @param tool [Tool] The tool to check
    # @return [Array<Hash>] Provider sets with missing credentials
    def self.unavailable_providers(tool)
      return [] if tool.required_credentials.blank?

      provider_sets = normalize_provider_sets(tool.required_credentials)
      provider_sets.reject { |ps| provider_set_ready?(ps) }
                   .map do |ps|
        missing = ps["credentials"].reject { |c| credential_exists?(c) }
        { "provider" => ps["provider"], "missing" => missing }
      end
    end

    # Human-readable summary of credential status
    # @param tool [Tool] The tool to check
    # @return [String, nil] Description of status, or nil if ready
    def self.missing_summary(tool)
      return nil if ready?(tool)
      return nil if tool.required_credentials.blank?

      provider_sets = normalize_provider_sets(tool.required_credentials)

      if provider_sets.length == 1
        # Single provider — simple message
        ps = provider_sets.first
        missing = ps["credentials"].reject { |c| credential_exists?(c) }
        names = missing.map { |c| c["description"] || "#{c['namespace']}.#{c['key']}" }

        case names.length
        when 1 then "Missing credential: #{names.first}"
        else "Missing credentials: #{names.join(', ')}"
        end
      else
        # Multiple providers — show status of each
        lines = provider_sets.map do |ps|
          if provider_set_ready?(ps)
            "  ✅ #{ps['provider']} — configured"
          else
            missing = ps["credentials"].reject { |c| credential_exists?(c) }
            names = missing.map { |c| c["description"] || c["key"] }
            "  ❌ #{ps['provider']} — missing: #{names.join(', ')}"
          end
        end

        "Requires one of these providers:\n#{lines.join("\n")}\n\nProvide credentials for at least one provider."
      end
    end

    # Return flat list of missing credential hashes across all provider sets
    # @param tool [Tool] The tool to check
    # @return [Array<Hash>] Missing credential entries
    def self.missing(tool)
      return [] if tool.required_credentials.blank?

      provider_sets = normalize_provider_sets(tool.required_credentials)

      # If any provider set is fully ready, nothing is "missing"
      return [] if provider_sets.any? { |ps| provider_set_ready?(ps) }

      # Return missing creds from the first provider set (or all for single-provider)
      if provider_sets.length == 1
        provider_sets.first["credentials"].reject { |c| credential_exists?(c) }
      else
        # For multi-provider, return all missing grouped by provider
        provider_sets.flat_map do |ps|
          ps["credentials"].reject { |c| credential_exists?(c) }
            .map { |c| c.merge("provider" => ps["provider"]) }
        end
      end
    end

    # --- Private helpers ---

    # Normalize flat list or multi-provider format into consistent provider sets
    def self.normalize_provider_sets(required_credentials)
      return [] if required_credentials.blank?

      first = required_credentials.first
      if first.is_a?(Hash) && first.key?("provider") && first.key?("credentials")
        # Already multi-provider format
        required_credentials
      else
        # Flat list — wrap in a single "default" provider set
        [ { "provider" => "default", "credentials" => required_credentials } ]
      end
    end

    def self.provider_set_ready?(provider_set)
      credentials = provider_set["credentials"] || []
      credentials.all? { |c| credential_exists?(c) }
    end

    def self.credential_exists?(cred)
      VaultEntry.exists?(
        namespace: cred["namespace"],
        key: cred["key"],
        agent_id: nil
      )
    end

    private_class_method :normalize_provider_sets, :provider_set_ready?, :credential_exists?
  end
end
