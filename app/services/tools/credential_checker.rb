# frozen_string_literal: true

module Tools
  # Checks if a tool's required credentials are present in the vault.
  # Used by ToolAvailability to give clear error messages when credentials are missing.
  class CredentialChecker
    # Check if all required credentials for a tool exist in the vault
    # @param tool [Tool] The tool to check
    # @return [Boolean] true if all credentials are present (or none required)
    def self.ready?(tool)
      missing(tool).empty?
    end

    # List missing credentials for a tool
    # @param tool [Tool] The tool to check
    # @return [Array<Hash>] Array of missing credential definitions
    def self.missing(tool)
      return [] if tool.required_credentials.blank?

      tool.required_credentials.reject do |cred|
        VaultEntry.exists?(
          namespace: cred["namespace"],
          key: cred["key"],
          agent_id: nil # Global entries only
        )
      end
    end

    # Human-readable summary of missing credentials
    # @param tool [Tool] The tool to check
    # @return [String, nil] Description of what's missing, or nil if ready
    def self.missing_summary(tool)
      missing_creds = missing(tool)
      return nil if missing_creds.empty?

      names = missing_creds.map { |c| c["description"] || "#{c['namespace']}.#{c['key']}" }

      case names.length
      when 1
        "Missing credential: #{names.first}"
      else
        "Missing credentials: #{names.join(', ')}"
      end
    end
  end
end
