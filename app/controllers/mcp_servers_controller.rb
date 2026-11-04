# frozen_string_literal: true

# Settings screen for MCP servers: list, add, edit, enable or disable, delete,
# and test the connection.
#
# Admin/owner only, since a stdio server runs a command in the workspace.
# Secret-looking env values and every auth header value go to the vault; the
# server row keeps only a "vault:" reference.
class McpServersController < ApplicationController
  before_action :authorize_admin_or_owner!
  before_action :set_server, only: %i[edit update destroy toggle_enabled test_connection]

  def index
    @servers = McpServer.order(:name)
  end

  def new
    @server = McpServer.new(transport: "stdio", enabled: true)
  end

  def create
    @server = McpServer.new(server_params)
    if @server.save
      redirect_to mcp_servers_path, notice: "MCP server '#{@server.name}' added. Use Test connection to discover its tools."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @server.update(server_params)
      redirect_to mcp_servers_path, notice: "MCP server '#{@server.name}' updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    Mcp::StdioRegistry.close(@server)
    @server.destroy!
    redirect_to mcp_servers_path, notice: "MCP server '#{@server.name}' deleted."
  end

  def toggle_enabled
    @server.update!(enabled: !@server.enabled)
    Mcp::StdioRegistry.close(@server) unless @server.enabled?
    redirect_to mcp_servers_path, notice: "MCP server '#{@server.name}' #{@server.enabled? ? 'enabled' : 'disabled'}."
  end

  # Connects to the server, discovers its tools, and reports the count or the error.
  def test_connection
    client = @server.stdio? ? Mcp::StdioClient : Mcp::HttpClient
    result = client.discover_tools(@server)

    if result.success?
      count = result.data[:tools].size
      redirect_to mcp_servers_path, notice: "Connected to '#{@server.name}'. Found #{count} #{'tool'.pluralize(count)}."
    else
      redirect_to mcp_servers_path, alert: "Could not connect to '#{@server.name}': #{result.error}"
    end
  end

  private

  def set_server
    @server = McpServer.find(params[:id])
  end

  def server_params
    permitted = params.require(:mcp_server).permit(:name, :transport, :command, :url, :npm_package, :enabled)
    env_text = params.dig(:mcp_server, :env_vars_text)
    auth_text = params.dig(:mcp_server, :auth_config_text)
    permitted[:env_vars] = vaulted_pairs(env_text, permitted[:name] || @server&.name, "env") { |k, v| secret_looking?(k) && !vault_ref?(v) } unless env_text.nil?
    permitted[:auth_config] = vaulted_pairs(auth_text, permitted[:name] || @server&.name, "auth") { |_k, v| !vault_ref?(v) } unless auth_text.nil?
    permitted
  end

  # Parses "KEY=value" lines into a hash, moving values the block selects into the vault.
  def vaulted_pairs(text, server_name, prefix)
    text.to_s.lines.filter_map { |line| line.strip.split("=", 2) if line.include?("=") }.to_h do |key, value|
      key = key.strip
      value = value.strip
      if value.present? && yield(key, value)
        namespace = "mcp_#{server_name.to_s.parameterize(separator: '_')}"
        vault_key = "#{prefix}_#{key.downcase.gsub(/[^a-z0-9]+/, '_')}"
        VaultEntry.find_or_initialize_by(namespace: namespace, key: vault_key).tap { |entry| entry.value = value }.save!
        value = "vault:#{namespace}/#{vault_key}"
      end
      [ key, value ]
    end
  end

  def vault_ref?(value)
    value.to_s.start_with?("vault:")
  end

  def secret_looking?(key)
    key.to_s.downcase.match?(/token|secret|key|password|credential/)
  end
end
