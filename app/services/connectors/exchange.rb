# frozen_string_literal: true

module Connectors
  # Shares a Connector as JSON. An export carries no vault values or even the
  # names of the exporter's vault keys: each secret field becomes a placeholder
  # reference the importer points at their own vault entry.
  class Exchange
    class Error < StandardError; end

    FORMAT = "hivemind-connector"
    VERSION = 1
    PLACEHOLDER_NAMESPACE = "replace_me"

    # @param connector [Connector]
    # @return [Hash] the shareable definition
    def self.export(connector)
      { "format" => FORMAT, "version" => VERSION, "name" => connector.name, "slug" => connector.slug,
        "description" => connector.description, "base_url" => connector.base_url,
        "auth_scheme" => connector.auth_scheme, "auth_config" => placeholder_auth(connector.auth_config),
        "operations" => connector.operations }
    end

    # @param text [String] JSON from {.export}
    # @return [Connector] an unsaved, disabled connector with a free slug
    # @raise [Error] when the text is not a connector export
    def self.build(text)
      doc = JSON.parse(text.to_s)
      raise Error, "That is not a Hivemind connector export" unless doc.is_a?(Hash) && doc["format"] == FORMAT

      Connector.new(doc.slice("name", "description", "base_url", "auth_scheme", "auth_config", "operations")
                       .merge("slug" => free_slug(doc["slug"].presence || doc["name"]), "enabled" => false))
    rescue JSON::ParserError
      raise Error, "That is not valid JSON"
    end

    def self.placeholder_auth(config)
      return {} unless config.is_a?(Hash)

      config.to_h do |key, value|
        [ key, Connector::PLAIN_AUTH_KEYS.include?(key) ? value : "vault:#{PLACEHOLDER_NAMESPACE}/#{key}" ]
      end
    end

    def self.free_slug(base)
      slug = base.to_s.parameterize(separator: "_").first(36)
      return slug unless Connector.exists?(slug: slug)

      (2..).lazy.map { |n| "#{slug}_#{n}" }.find { |candidate| !Connector.exists?(slug: candidate) }
    end

    private_class_method :placeholder_auth, :free_slug
  end
end
