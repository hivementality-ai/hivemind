# frozen_string_literal: true

module Tools
  # Lets an agent draft a connector for an HTTP API; a person approves it before it runs.
  class CreateConnectorExecutor < BaseExecutor
    def call
      result = Agents::ConnectorCreator.call(
        agent: agent,
        name: input["name"].to_s.strip,
        slug: input["slug"].to_s.strip,
        base_url: input["base_url"].to_s.strip,
        auth_scheme: input["auth_scheme"].to_s.strip,
        auth_config: input["auth_config"].is_a?(Hash) ? input["auth_config"] : {},
        operations: input["operations"].is_a?(Array) ? input["operations"] : [],
        description: input["description"].presence
      )
      return ServiceResponse.failure(error: result.error) unless result.success?

      ServiceResponse.success(data: { output: result.data[:output], exit_code: 0 })
    end
  end
end
