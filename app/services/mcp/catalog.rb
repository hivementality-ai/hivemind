# frozen_string_literal: true

module Mcp
  # The starter list of official remote MCP servers, read from config/mcp_catalog.yml.
  class Catalog
    Entry = Struct.new(:key, :name, :summary, :url, :docs, keyword_init: true)

    PATH = Rails.root.join("config/mcp_catalog.yml")

    # @return [Array<Entry>] every catalog entry in file order
    def self.entries
      @entries ||= YAML.safe_load_file(PATH).fetch("servers").map { |row| Entry.new(**row.symbolize_keys) }.freeze
    end

    # @param key [String] catalog key such as "notion"
    # @return [Entry, nil]
    def self.find(key)
      entries.find { |entry| entry.key == key.to_s }
    end

    # @param entry [Entry]
    # @return [McpServer, nil] the already-added server for this entry, matched by URL
    def self.server_for(entry)
      McpServer.find_by(url: entry.url)
    end
  end
end
