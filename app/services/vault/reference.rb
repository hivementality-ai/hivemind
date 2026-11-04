# frozen_string_literal: true

module Vault
  # A pointer to a vault entry written "vault:namespace/key". Connectors and
  # agent-made tools hold references, never secret values.
  class Reference
    PATTERN = %r{\Avault:(?<namespace>[A-Za-z0-9_.-]+)/(?<key>[A-Za-z0-9_.-]+)\z}

    # @param value [Object] candidate reference
    # @return [Boolean] true when value is a well-formed vault reference
    def self.valid?(value)
      value.is_a?(String) && PATTERN.match?(value)
    end

    # @param value [String] a vault reference
    # @return [Hash, nil] +{ namespace:, key: }+, or nil when malformed
    def self.parse(value)
      match = value.is_a?(String) ? PATTERN.match(value) : nil
      match && { namespace: match[:namespace], key: match[:key] }
    end

    # Reads the referenced secret (audited).
    #
    # @param value [String] a vault reference
    # @param agent [Agent, nil] agent whose scoped entries take priority
    # @return [ServiceResponse] success with +data[:value]+, or failure
    def self.resolve(value, agent: nil)
      parts = parse(value)
      return ServiceResponse.failure(error: "Not a vault reference") unless parts

      Vault::Read.call(namespace: parts[:namespace], key: parts[:key], agent: agent)
    end
  end
end
