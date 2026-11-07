# frozen_string_literal: true

require "shellwords"

module Mcp
  # The starter shelf of official MCP servers, read from config/mcp_catalog.yml.
  #
  # An entry is either remote (a +url+, signed in with OAuth) or local (a stdio
  # +command+ with +args+). A local entry may ask for +inputs+: an "arg" input
  # fills a +{key}+ placeholder in +args+, an "env" input becomes an environment
  # variable, and a "secret" input is an environment variable kept in the vault.
  class Catalog
    # One thing the person fills in before a local server can start.
    Input = Struct.new(:key, :label, :type, :placeholder, :help, :required, keyword_init: true) do
      def secret?
        type == "secret"
      end

      def arg?
        type == "arg"
      end

      def required?
        required != false
      end
    end

    Entry = Struct.new(:key, :name, :category, :summary, :url, :command, :args, :inputs, :docs, keyword_init: true) do
      def remote?
        url.present?
      end

      def local?
        !remote?
      end

      # @return [Array<Input>]
      def input_list
        Array(inputs).map { |row| Input.new(**row.symbolize_keys) }
      end

      # @return [Boolean] whether the person has to fill something in before it can be added
      def inputs?
        input_list.any?
      end

      # @param server [McpServer]
      # @return [Boolean] whether the server is this entry's added copy
      def added_as?(server)
        remote? ? server.url == url : server.metadata.to_h["catalog_key"] == key
      end

      # @param values [Hash{String=>String}] the filled-in arg inputs by key
      # @return [String] the shell command line for a local entry
      def command_line(values = {})
        words = Array(args).map { |arg| arg.gsub(/\{(\w+)\}/) { values[Regexp.last_match(1)].to_s } }
        ([ command ] + words).shelljoin
      end
    end

    PATH = Rails.root.join("config/mcp_catalog.yml")

    # @return [Array<Entry>] every catalog entry in file order
    def self.entries
      @entries ||= YAML.safe_load_file(PATH).fetch("servers").map { |row| Entry.new(**row.symbolize_keys) }.freeze
    end

    # @return [Array<String>] the categories in the order they first appear
    def self.categories
      entries.map(&:category).uniq
    end

    # @param key [String] catalog key such as "notion"
    # @return [Entry, nil]
    def self.find(key)
      entries.find { |entry| entry.key == key.to_s }
    end

    # @param entry [Entry]
    # @return [McpServer, nil] the already-added server for this entry
    def self.server_for(entry)
      return McpServer.find_by(url: entry.url) if entry.remote?

      McpServer.where("metadata ->> 'catalog_key' = ?", entry.key).first
    end
  end
end
