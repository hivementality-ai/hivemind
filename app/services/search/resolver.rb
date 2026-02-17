# frozen_string_literal: true

module Search
  class Resolver
    PROVIDERS = %w[brave searchapi serpapi duckduckgo].freeze

    def self.provider
      name = VaultEntry.find_by(namespace: "search", key: "provider")&.value
      api_key = VaultEntry.find_by(namespace: "search", key: "api_key")&.value

      case name
      when "brave"     then api_key.present? ? Search::Brave.new(api_key) : fallback
      when "searchapi" then api_key.present? ? Search::Searchapi.new(api_key) : fallback
      when "serpapi"    then api_key.present? ? Search::Serpapi.new(api_key) : fallback
      else fallback
      end
    end

    def self.configured?
      name = VaultEntry.find_by(namespace: "search", key: "provider")&.value
      api_key = VaultEntry.find_by(namespace: "search", key: "api_key")&.value
      name.present? && name != "duckduckgo" && api_key.present?
    end

    def self.current_provider_name
      VaultEntry.find_by(namespace: "search", key: "provider")&.value || "duckduckgo"
    end

    def self.fallback
      Search::Duckduckgo.new
    end
  end
end
