# frozen_string_literal: true

module Swarms
  module Deployers
    # Creates or updates ApiIntegration records from a SwarmDocument's
    # api_integrations[] section.
    #
    # Each api_integration entry in the swarm document is a plain Hash (as
    # produced by SwarmParser#normalize_array) with indifferent-access keys.
    #
    # API integrations are matched by name. Resolution strategies are keyed by name:
    #   :skip      – keep existing integration, return it in the results
    #   :overwrite – update existing integration attributes with swarm values
    #   :rename    – create new integration with an auto-suffixed name
    #   (none)     – create new integration (no conflict expected)
    #
    # The payload always contains an :api_integrations array of DeployResult
    # value objects, one per integration in the document, in document order.
    #
    # Usage:
    #   result = ApiIntegrationsDeployer.call(document: swarm_doc, resolutions: {})
    #   result.success?                   # => true / false
    #   result.payload[:api_integrations] # => [DeployResult, ...]
    class ApiIntegrationsDeployer
      # Outcome for a single deployed API integration.
      DeployResult = Data.define(:name, :record, :action) do
        # action is one of: :created, :updated, :skipped, :renamed
      end

      def self.call(document:, resolutions: {})
        new(document, resolutions).call
      end

      def initialize(document, resolutions)
        @document    = document
        @resolutions = resolutions.with_indifferent_access
      end

      def call
        results = @document.api_integrations.map do |integration_hash|
          deploy_integration(integration_hash.with_indifferent_access)
        end

        ServiceResponse.success(payload: { api_integrations: results })
      rescue ActiveRecord::RecordInvalid => e
        ServiceResponse.error(message: "Failed to deploy API integrations: #{e.record.errors.full_messages.join(', ')}")
      rescue StandardError => e
        ServiceResponse.error(message: "Failed to deploy API integrations: #{e.message}")
      end

      private

      def deploy_integration(integration_hash)
        name     = integration_hash[:name].to_s
        strategy = @resolutions[name]&.to_sym
        existing = ApiIntegration.find_by(name: name)

        if existing.nil?
          record = create_integration(name, integration_hash)
          DeployResult.new(name: name, record: record, action: :created)
        else
          apply_strategy(strategy, existing, name, integration_hash)
        end
      end

      def create_integration(name, integration_hash)
        ApiIntegration.create!(build_attributes(name, integration_hash))
      end

      def apply_strategy(strategy, existing, name, integration_hash)
        case strategy
        when :skip
          DeployResult.new(name: name, record: existing, action: :skipped)
        when :overwrite
          existing.update!(build_attributes(name, integration_hash))
          DeployResult.new(name: name, record: existing, action: :updated)
        when :rename
          new_name = unique_name(name)
          record   = create_integration(new_name, integration_hash.merge(name: new_name))
          DeployResult.new(name: new_name, record: record, action: :renamed)
        else
          # No resolution provided but conflict exists — skip to be safe.
          DeployResult.new(name: name, record: existing, action: :skipped)
        end
      end

      def build_attributes(name, integration_hash)
        attrs = {
          name:            name,
          base_url:        integration_hash[:base_url].to_s,
          enabled:         integration_hash.key?(:enabled) ? integration_hash[:enabled] : true,
          auth_config:     (integration_hash[:auth_config].presence    || {}),
          default_headers: (integration_hash[:default_headers].presence || {}),
          endpoints:       (integration_hash[:endpoints].presence      || []),
          spec_data:       (integration_hash[:spec_data].presence      || {})
        }

        attrs[:description]       = integration_hash[:description].presence if integration_hash[:description].present?
        attrs[:spec_format]       = integration_hash[:spec_format].presence  if integration_hash[:spec_format].present?
        attrs[:timeout_seconds]   = integration_hash[:timeout_seconds]       if integration_hash[:timeout_seconds].present?
        attrs[:max_response_bytes] = integration_hash[:max_response_bytes]   if integration_hash[:max_response_bytes].present?

        attrs
      end

      # Appends an incrementing suffix until the name is unique.
      def unique_name(base)
        candidate = "#{base}-2"
        counter   = 2

        while ApiIntegration.exists?(name: candidate)
          counter  += 1
          candidate = "#{base}-#{counter}"
        end

        candidate
      end
    end
  end
end
