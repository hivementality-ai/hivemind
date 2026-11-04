# frozen_string_literal: true

module Tools
  # Runs a connector operation exposed through Connectors::ToolProxy.
  class ConnectorExecutor < BaseExecutor
    def call
      connector = Connector.find_by(id: config[:connector_id])
      return ServiceResponse.failure(error: "Connector not found") unless connector

      result = Connectors::Executor.call(
        connector: connector,
        operation: config[:operation],
        params: input,
        agent: agent
      )
      return ServiceResponse.failure(error: result.error) unless result.success?

      ServiceResponse.success(data: { output: result.data[:output], exit_code: 0 })
    end
  end
end
