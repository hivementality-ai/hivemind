# frozen_string_literal: true

module Agents
  # Proposes a corrected operations list (and optionally base URL) for a connector
  # whose calls keep failing. Nothing changes until a person approves the before/after
  # diff. Auth settings and secrets are out of reach: the proposal cannot carry them.
  class ConnectorFixProposer
    FORBIDDEN_KEYS = %w[auth_config auth_scheme secret secrets api_key token password].freeze

    # @param agent [Agent]
    # @param slug [String] connector slug
    # @param operations [Array<Hash>] the full corrected operations list
    # @param base_url [String, nil]
    # @param extra [Hash] any other input the agent supplied, checked for auth changes
    # @return [ServiceResponse] success with +data[:output]+ and +data[:approval_id]+
    def self.call(agent:, slug:, operations:, base_url: nil, extra: {})
      new(agent:, slug:, operations:, base_url:, extra:).call
    end

    def initialize(agent:, slug:, operations:, base_url:, extra:)
      @agent = agent
      @slug = slug
      @operations = operations
      @base_url = base_url.presence
      @extra = extra.to_h.stringify_keys
    end

    def call
      return refuse("Connector fixes cannot change authentication or secrets") if (@extra.keys & FORBIDDEN_KEYS).any?

      connector = Connector.find_by(slug: @slug)
      return refuse("Connector #{@slug} not found") unless connector
      return refuse("Connector #{@slug} is waiting for approval and cannot be fixed yet") if connector.pending_approval?

      candidate = Connector.find(connector.id)
      candidate.assign_attributes(operations: @operations, base_url: @base_url || connector.base_url)
      return refuse("Fix rejected: #{candidate.errors.full_messages.to_sentence}") unless candidate.valid?

      changes = diff(connector, candidate)
      return refuse("The proposed definition is identical to the current one") if changes.empty?

      request_approval(connector, candidate, changes)
    rescue StandardError => e
      refuse("Fix proposal failed: #{e.message}")
    end

    private

    def refuse(message)
      ServiceResponse.failure(error: message)
    end

    def diff(connector, candidate)
      before = connector.operations.index_by { |op| op["name"] }
      after = candidate.operations.index_by { |op| op["name"] }
      changes = (before.keys | after.keys).filter_map do |name|
        next if before[name] == after[name]

        { "name" => name, "change" => change_kind(before[name], after[name]), "before" => before[name], "after" => after[name] }
      end
      changes << { "name" => "base_url", "change" => "changed", "before" => connector.base_url, "after" => candidate.base_url } if connector.base_url != candidate.base_url
      changes
    end

    def change_kind(before, after)
      return "added" if before.nil?

      after.nil? ? "removed" : "changed"
    end

    def request_approval(connector, candidate, changes)
      result = Approvals::Request.call(
        agent: @agent,
        action: "update_connector",
        resource: "Connector##{connector.id}",
        params: {
          connector_id: connector.id,
          slug: connector.slug,
          base_url_after: candidate.base_url,
          operations: candidate.operations,
          changes: changes
        }
      )
      return refuse(Array(result.error).to_sentence) unless result.success?

      ServiceResponse.success(data: {
        output: "Fix for '#{connector.slug}' (#{changes.map { |c| c['name'] }.join(', ')}) is waiting for the user to approve. " \
                "Nothing changes until they do.",
        approval_id: result.data[:approval].id
      })
    end
  end
end
