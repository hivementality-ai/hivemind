# frozen_string_literal: true

module Mcp
  # Reads the +mcpServers+ section of a Claude Desktop config and turns the
  # entries into McpServer rows. Env values and header values go to the vault
  # (namespace +mcp_import_<server>+); the row keeps only "vault:" references.
  class DesktopImport
    class Error < StandardError; end

    CONFIG_PATH = File.expand_path("~/Library/Application Support/Claude/claude_desktop_config.json")

    Entry = Struct.new(:name, :command, :args, :env, :url, :headers, :transport, keyword_init: true) do
      # @return [Boolean] true when the entry runs a local command
      def stdio?
        transport == "stdio"
      end

      # @return [String] what the preview shows: the command (without its arguments, which can hold keys) or the URL
      def target
        stdio? ? command : url
      end

      # @return [Hash] a plain hash that survives JSON
      def to_payload
        to_h.stringify_keys
      end
    end

    # @return [String, nil] the desktop config text when this machine has a readable one
    def self.read_local
      File.read(CONFIG_PATH) if File.file?(CONFIG_PATH) && File.readable?(CONFIG_PATH)
    end

    # @param text [String] claude_desktop_config.json contents
    # @return [Array<Entry>] the importable entries, in file order
    # @raise [Error] when the text is not a config with an mcpServers object
    def self.parse(text)
      servers = JSON.parse(text.to_s).then { |doc| doc.is_a?(Hash) ? doc["mcpServers"] : nil }
      raise Error, "No mcpServers found in that config" unless servers.is_a?(Hash) && servers.any?

      servers.filter_map { |name, config| build_entry(name, config) }
    rescue JSON::ParserError
      raise Error, "That is not valid JSON"
    end

    # @param payloads [Array<Hash>] +Entry#to_payload+ hashes
    # @return [Hash] +{ imported: [names], skipped: [names] }+; existing names are skipped
    def self.import!(payloads)
      result = { imported: [], skipped: [] }
      payloads.each do |payload|
        entry = Entry.new(**payload.symbolize_keys)
        (create_server(entry) ? result[:imported] : result[:skipped]) << entry.name
      end
      result
    end

    def self.build_entry(name, config)
      return unless config.is_a?(Hash)

      url = config["url"].presence
      return unless url || config["command"].present?

      Entry.new(name: name.to_s, command: config["command"], args: Array(config["args"]).map(&:to_s),
                env: string_hash(config["env"]), url: url, headers: string_hash(config["headers"]),
                transport: url ? (config["type"].to_s == "sse" ? "sse" : "http") : "stdio")
    end

    def self.string_hash(value)
      value.is_a?(Hash) ? value.to_h { |k, v| [ k.to_s, v.to_s ] } : {}
    end

    def self.create_server(entry)
      return false if McpServer.exists?(name: entry.name)

      namespace = "mcp_import_#{entry.name.parameterize(separator: '_')}"
      server = McpServer.new(name: entry.name, transport: entry.transport, enabled: true,
                             command: entry.stdio? ? Shellwords.join([ entry.command, *entry.args ]) : nil,
                             url: entry.url)
      return false unless server.valid?

      McpServer.transaction do
        server.env_vars = vault_all(namespace, "env", entry.env)
        server.auth_config = vault_all(namespace, "auth", entry.headers)
        server.save!
        server.assign_to_visible_agents!
      end
      true
    end

    def self.vault_all(namespace, prefix, pairs)
      pairs.to_h do |key, value|
        vault_key = "#{prefix}_#{key.downcase.gsub(/[^a-z0-9]+/, '_')}"
        VaultEntry.find_or_initialize_by(namespace: namespace, key: vault_key).tap { |e| e.value = value }.save!
        [ key, "vault:#{namespace}/#{vault_key}" ]
      end
    end

    private_class_method :build_entry, :string_hash, :create_server, :vault_all
  end
end
