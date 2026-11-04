# frozen_string_literal: true

module Agents
  # Drafts a Connector on behalf of an agent. The connector is saved disabled and
  # pending approval; a person stores the key in the vault and approves it. The
  # agent only ever passes vault references, never a secret value.
  class ConnectorCreator
    # @param agent [Agent] the drafting agent
    # @param name [String] display name, e.g. "Notion"
    # @param slug [String] snake_case id used in tool names
    # @param base_url [String] API base URL
    # @param auth_scheme [String] one of Connector::AUTH_SCHEMES
    # @param auth_config [Hash] non-secret settings plus "vault:namespace/key" references
    # @param operations [Array<Hash>] operation definitions
    # @param description [String, nil]
    # @return [ServiceResponse] success with +data[:connector_id]+ and +data[:status]+
    def self.call(agent:, name:, slug:, base_url:, auth_scheme:, auth_config:, operations:, description: nil)
      new(agent:, name:, slug:, base_url:, auth_scheme:, auth_config:, operations:, description:).call
    end

    def initialize(agent:, name:, slug:, base_url:, auth_scheme:, auth_config:, operations:, description:)
      @agent = agent
      @attributes = { name:, slug:, base_url:, auth_scheme:, auth_config:, operations:, description: }
    end

    def call
      connector = Connector.new(@attributes.merge(enabled: false, pending_approval: true, created_by: @agent))
      unless connector.valid?
        return ServiceResponse.failure(error: "Connector rejected: #{connector.errors.full_messages.to_sentence}")
      end

      connector.save!
      request_approval(connector)

      ServiceResponse.success(data: {
        output: instructions(connector),
        connector_id: connector.id,
        status: "pending_approval"
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Connector creation failed: #{e.message}")
    end

    private

    def request_approval(connector)
      Approvals::Request.call(
        agent: @agent,
        action: "create_connector",
        resource: "Connector##{connector.id}",
        params: {
          connector_id: connector.id,
          name: connector.name,
          slug: connector.slug,
          base_url: connector.base_url,
          auth_scheme: connector.auth_scheme,
          secret_refs: secret_refs(connector),
          operations: connector.operations.map { |op| op.slice("name", "method", "path", "read_only") }
        }
      )
    end

    def secret_refs(connector)
      connector.auth_config.values.select { |value| Vault::Reference.valid?(value) }
    end

    def instructions(connector)
      refs = secret_refs(connector)
      ask = refs.any? ? "Ask the user to store the key in the vault at #{refs.join(', ')}, then approve it." : "Ask the user to approve it."
      "Connector '#{connector.slug}' saved disabled and waiting for approval. #{ask} " \
        "After approval, test one read-only operation."
    end
  end
end
