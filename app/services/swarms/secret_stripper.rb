# frozen_string_literal: true

module Swarms
  # Scans a serialized swarm manifest Hash for sensitive values and replaces them
  # with vault: references.
  #
  # "Sensitive" means any value that looks like an API key, secret token, or
  # password. Detection is pattern-based — common prefixes (sk-, ghp_, Bearer,
  # etc.) and high-entropy strings in known secret field names.
  #
  # Replacements use the convention:
  #   "vault:swarm_export/<sanitized_field_path>"
  #
  # This means the exported .swarm.json can be safely committed or shared; the
  # recipient must populate the vault entries before importing.
  #
  # Usage:
  #   result = SecretStripper.call(manifest: hash)
  #   result.success?                  # => always true (stripping never fails)
  #   result.payload[:manifest]        # => manifest with secrets replaced
  #   result.payload[:stripped_count]  # => number of values replaced
  #   result.payload[:stripped_paths]  # => Array of dot-notation paths replaced
  #
  class SecretStripper
    # Field name patterns that are almost always secret values.
    SECRET_FIELD_NAMES = %w[
      api_key apikey api_secret secret token password passwd secret_key
      access_token refresh_token auth_token bearer_token private_key
      client_secret consumer_secret webhook_secret signing_secret
      encryption_key database_url db_password db_pass
    ].freeze

    SECRET_FIELD_PATTERN = Regexp.union(
      SECRET_FIELD_NAMES.map { |name| /\A#{Regexp.escape(name)}\z/i }
    ).freeze

    # Value patterns that look like secrets regardless of field name.
    SECRET_VALUE_PATTERNS = [
      /\Ask-[A-Za-z0-9]{20,}\z/,               # OpenAI-style keys (sk-...)
      /\Ask-proj-[A-Za-z0-9\-_]{20,}\z/,       # OpenAI project keys
      /\Aghp_[A-Za-z0-9]{36,}\z/,              # GitHub personal access tokens
      /\Aghs_[A-Za-z0-9]{36,}\z/,              # GitHub Actions secrets
      /\Axoxb-[0-9]+-[A-Za-z0-9\-]+\z/,       # Slack bot tokens
      /\Axoxp-[0-9]+-[A-Za-z0-9\-]+\z/,       # Slack user tokens
      /\Abearer\s+[A-Za-z0-9\-_.~+\/]+=*\z/i,  # Bearer tokens
      /\Aey[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\z/, # JWTs
    ].freeze

    # vault: references must not be double-stripped.
    VAULT_PREFIX = "vault:"

    def self.call(manifest:)
      new(manifest:).call
    end

    def initialize(manifest:)
      @manifest       = manifest
      @stripped_paths = []
    end

    def call
      stripped_manifest = strip_recursive(@manifest, path: [])

      ServiceResponse.success(
        payload: {
          manifest:       stripped_manifest,
          stripped_count: @stripped_paths.size,
          stripped_paths: @stripped_paths.dup
        }
      )
    end

    private

    # Recursively walk the manifest. Returns a new structure with secrets replaced.
    def strip_recursive(value, path:)
      case value
      when Hash
        value.each_with_object({}) do |(k, v), result|
          result[k] = strip_recursive(v, path: path + [k.to_s])
        end
      when Array
        value.each_with_index.map do |item, idx|
          strip_recursive(item, path: path + [idx.to_s])
        end
      when String
        strip_string(value, path:)
      else
        value
      end
    end

    # Returns either the original string or a vault: replacement.
    def strip_string(value, path:)
      return value if value.blank?
      return value if value.start_with?(VAULT_PREFIX)

      field_name = path.last.to_s

      if secret_field_name?(field_name) && value_looks_like_secret?(value)
        record_and_replace(path)
      elsif secret_value_pattern?(value)
        record_and_replace(path)
      else
        value
      end
    end

    def record_and_replace(path)
      @stripped_paths << path.join(".")
      build_vault_ref(path)
    end

    def secret_field_name?(name)
      SECRET_FIELD_PATTERN.match?(name)
    end

    # A value "looks like a secret" when it is not obviously human-readable prose.
    # Guard: skip URLs, template placeholders, very short values, and space-separated
    # prose so we do not wrongly strip e.g. a field named "token" with value "Bearer".
    def value_looks_like_secret?(value)
      return false if value.length < 8
      return false if value.start_with?("http://", "https://", "{{", VAULT_PREFIX)
      return false if value.include?(" ") && value.length < 80

      true
    end

    def secret_value_pattern?(value)
      SECRET_VALUE_PATTERNS.any? { |pattern| pattern.match?(value) }
    end

    # Builds a deterministic vault: reference from the field path.
    # e.g. ["agents", "0", "model_config", "api_key"]
    #   => "vault:swarm_export/agents.0.model_config.api_key"
    def build_vault_ref(path)
      key = path.join(".").gsub(/[^A-Za-z0-9._-]/, "_").downcase
      "#{VAULT_PREFIX}swarm_export/#{key}"
    end
  end
end
