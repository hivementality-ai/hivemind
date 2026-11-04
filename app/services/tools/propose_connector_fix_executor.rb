# frozen_string_literal: true

module Tools
  # Lets an agent propose a corrected definition for a failing connector; a person approves it.
  class ProposeConnectorFixExecutor < BaseExecutor
    HANDLED_KEYS = %w[slug operations base_url].freeze

    def call
      result = Agents::ConnectorFixProposer.call(
        agent: agent,
        slug: input["slug"].to_s.strip,
        operations: input["operations"].is_a?(Array) ? input["operations"] : [],
        base_url: input["base_url"].to_s.strip,
        extra: input.to_h.stringify_keys.except(*HANDLED_KEYS)
      )
      return ServiceResponse.failure(error: result.error) unless result.success?

      ServiceResponse.success(data: { output: result.data[:output], exit_code: 0 })
    end
  end
end
