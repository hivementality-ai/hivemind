# frozen_string_literal: true

module Vault
  class Read
    def self.call(namespace:, key:, agent: nil)
      new(namespace:, key:, agent:).call
    end

    def initialize(namespace:, key:, agent: nil)
      @namespace = namespace
      @key = key
      @agent = agent
    end

    def call
      entry = VaultEntry.resolve(namespace: @namespace, key: @key, agent: @agent)

      unless entry
        return ServiceResponse.failure(error: "Secret not found: #{@namespace}/#{@key}")
      end

      Audit::Record.call(
        actor_type: @agent ? "agent" : "system",
        actor_id: @agent&.id || "system",
        action: "vault.read",
        resource: "vault_entries/#{entry.id}",
        metadata: { namespace: @namespace, key: @key }
      )

      ServiceResponse.success(data: { value: entry.encrypted_value })
    end
  end
end
