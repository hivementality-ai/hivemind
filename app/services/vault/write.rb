# frozen_string_literal: true

module Vault
  class Write
    def self.call(namespace:, key:, value:, agent: nil, metadata: {})
      new(namespace:, key:, value:, agent:, metadata:).call
    end

    def initialize(namespace:, key:, value:, agent: nil, metadata: {})
      @namespace = namespace
      @key = key
      @value = value
      @agent = agent
      @metadata = metadata
    end

    def call
      entry = VaultEntry.find_or_initialize_by(
        namespace: @namespace,
        key: @key,
        agent_id: @agent&.id
      )

      entry.encrypted_value = @value
      entry.metadata = (entry.metadata || {}).merge(@metadata)

      if entry.save
        action = entry.previously_new_record? ? "vault.create" : "vault.update"

        Audit::Record.call(
          actor_type: @agent ? "agent" : "system",
          actor_id: @agent&.id || "system",
          action:,
          resource: "vault_entries/#{entry.id}",
          metadata: { namespace: @namespace, key: @key }
        )

        ServiceResponse.success(data: { entry: })
      else
        ServiceResponse.failure(error: entry.errors.full_messages)
      end
    end
  end
end
