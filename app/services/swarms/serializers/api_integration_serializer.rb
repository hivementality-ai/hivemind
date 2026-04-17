# frozen_string_literal: true

module Swarms
  module Serializers
    # Converts an ApiIntegration record into a swarm api_integrations[] entry hash.
    #
    # Auth credentials are intentionally included as-is here — SecretStripper in
    # the export pipeline will replace any sensitive values with vault: references
    # before the file is delivered to the user.
    #
    # Usage:
    #   hash = ApiIntegrationSerializer.call(api_integration: record)
    #   # => { "name" => "...", "base_url" => "https://...", ... }
    class ApiIntegrationSerializer
      def self.call(api_integration:)
        new(api_integration).call
      end

      def initialize(api_integration)
        @integration = api_integration
      end

      def call
        hash = {
          "name"     => @integration.name,
          "base_url" => @integration.base_url
        }

        hash["description"]     = @integration.description    if @integration.description.present?
        hash["auth_config"]     = @integration.auth_config     if @integration.auth_config.present?
        hash["default_headers"] = @integration.default_headers if @integration.default_headers.present?
        hash["endpoints"]       = @integration.endpoints       if @integration.endpoints.present?
        hash["spec_format"]     = @integration.spec_format     if @integration.spec_format.present?
        hash["spec_data"]       = @integration.spec_data       if @integration.spec_data.present?
        hash["timeout_seconds"]    = @integration.timeout_seconds    if @integration.timeout_seconds.present?
        hash["max_response_bytes"] = @integration.max_response_bytes if @integration.max_response_bytes.present?
        hash["enabled"]            = @integration.enabled             unless @integration.enabled.nil?

        hash
      end
    end
  end
end
