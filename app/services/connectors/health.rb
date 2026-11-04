# frozen_string_literal: true

module Connectors
  # Tracks consecutive definition-shaped failures per connector operation. A wrong
  # path, method or parameter shape means the definition is stale; timeouts, 5xx and
  # 429 say nothing about it and never count. Health lives in +connector.health+ as
  # +{ operation => { consecutive_failures, last_error_class, last_status, last_failure_at } }+.
  module Health
    REPAIR_THRESHOLD = 3
    DEFINITION_STATUSES = [ 404, 405 ].freeze
    SCHEMA_STATUSES = [ 400, 422 ].freeze
    SCHEMA_HINT = /schema|invalid|required|missing|unknown|unrecognized|unexpected|unsupported|malformed|validation|not allowed|must be/i
    HINT = "This connector may be out of date. You can propose a fix with propose_connector_fix."

    module_function

    # @param status [Integer, nil] HTTP status, nil when no response arrived
    # @param body [String, nil] response body
    # @return [Symbol] :definition, :transient or :other
    def classify(status, body = nil)
      return :transient if status.nil? || status >= 500 || [ 408, 429 ].include?(status)
      return :definition if DEFINITION_STATUSES.include?(status)
      return :definition if SCHEMA_STATUSES.include?(status) && SCHEMA_HINT.match?(body.to_s)

      :other
    end

    # Records a failed call. Only definition-shaped failures advance the count.
    #
    # @param connector [Connector]
    # @param operation [String]
    # @param kind [Symbol] result of {classify}
    # @param status [Integer, nil]
    # @return [Integer] the operation's consecutive definition-failure count
    def record_failure(connector, operation, kind, status: nil)
      connector.with_lock do
        entry = connector.health.fetch(operation, {})
        count = entry.fetch("consecutive_failures", 0)
        count += 1 if kind == :definition
        entry = { "consecutive_failures" => count, "last_error_class" => kind.to_s,
                  "last_status" => status, "last_failure_at" => Time.current.iso8601 }
        connector.update_columns(health: connector.health.merge(operation => entry))
        count
      end
    end

    # Clears the operation's failure record after a successful call.
    def record_success(connector, operation)
      return unless connector.health.key?(operation)

      connector.with_lock { connector.update_columns(health: connector.health.except(operation)) }
    end

    # @return [Boolean] true when the count is high enough to suggest a fix
    def repair_suggested?(count)
      count >= REPAIR_THRESHOLD
    end
  end
end
