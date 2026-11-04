# frozen_string_literal: true

# Settings screen for MCP servers: list, add, edit, enable or disable, delete,
# and test the connection.
#
# Admin/owner only, since a stdio server runs a command in the workspace.
# Secret-looking env values and every auth header value go to the vault; the
# server row keeps only a "vault:" reference.
class McpServersController < ApplicationController
  before_action :authorize_admin_or_owner!
  before_action :set_server, only: %i[edit update destroy toggle_enabled test_connection oauth_connect oauth_callback oauth_disconnect]

  def index
    @servers = McpServer.order(:name)
  end

  def new
    @server = McpServer.new(transport: "stdio", enabled: true)
  end

  def create
    @server = McpServer.new(server_params)
    if @server.save
      flush_vault_writes
      redirect_to mcp_servers_path, notice: "MCP server '#{@server.name}' added. Use Test connection to discover its tools."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  # Adds a starter-catalog server (or reuses the one already added) and goes straight into its OAuth sign-in.
  def add_from_catalog
    entry = Mcp::Catalog.find(params[:key])
    return redirect_to integrations_path, alert: "Unknown catalog server." unless entry

    @server = Mcp::Catalog.server_for(entry) || McpServer.create(name: free_catalog_name(entry), transport: "http", url: entry.url)
    return redirect_to(integrations_path, alert: @server.errors.full_messages.to_sentence) unless @server.persisted?

    start_oauth(integrations_path)
  end

  def update
    if @server.update(server_params)
      flush_vault_writes
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

  # Discovers the server's authorization server and sends the browser there.
  def oauth_connect
    start_oauth(mcp_servers_path)
  end

  # Return leg of the authorization flow: swaps the code for tokens, then discovers tools.
  def oauth_callback
    if params[:error].present?
      return redirect_to mcp_servers_path, alert: "'#{@server.name}' was not authorized: #{params[:error_description].presence || params[:error]}"
    end

    Mcp::OAuth.complete!(@server, code: params[:code].to_s, state: params[:state].to_s)
    result = Mcp::HttpClient.discover_tools(@server)
    notice = result.success? ? "Connected to '#{@server.name}'." : "Authorized '#{@server.name}', but tool discovery failed: #{result.error}"
    redirect_to mcp_servers_path, notice: notice
  rescue Mcp::OAuth::Error => e
    redirect_to mcp_servers_path, alert: "Could not authorize '#{@server.name}': #{e.message}"
  end

  def oauth_disconnect
    VaultEntry.where(namespace: "mcp_oauth_#{@server.id}").delete_all
    @server.mark_disconnected!
    redirect_to mcp_servers_path, notice: "Signed out of '#{@server.name}'."
  end

  private

  # The catalog name, or "Name (catalog)", "Name (catalog) 2" and so on when a different server already uses it.
  def free_catalog_name(entry)
    return entry.name unless McpServer.exists?(name: entry.name)

    base = "#{entry.name} (catalog)"
    candidates = [ base ].lazy + (2..).lazy.map { |n| "#{base} #{n}" }
    candidates.find { |name| !McpServer.exists?(name: name) }
  end

  # Sends the browser to the server's authorization page, or back to +return_to+ with the reason it failed.
  def start_oauth(return_to)
    return redirect_to(return_to, alert: "Only remote servers can use OAuth.") unless @server.remote?

    redirect_to Mcp::OAuth.authorization_url(@server, redirect_uri: oauth_redirect_uri), allow_other_host: true
  rescue Mcp::OAuth::Error => e
    redirect_to return_to, alert: "Could not connect '#{@server.name}': #{e.message}"
  end

  # Built from the configured canonical host when set, otherwise from the request.
  def oauth_redirect_uri
    base = RemoteAccess::ConfigStore.canonical_host.presence || request.base_url
    "#{base.chomp('/')}#{oauth_callback_mcp_server_path(@server)}"
  end

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
        (@vault_writes ||= []) << [ namespace, vault_key, value ]
        value = "vault:#{namespace}/#{vault_key}"
      end
      [ key, value ]
    end
  end

  # Stores the secrets collected while parsing; only runs once the record is saved.
  def flush_vault_writes
    Array(@vault_writes).each do |namespace, key, value|
      VaultEntry.find_or_initialize_by(namespace: namespace, key: key).tap { |entry| entry.value = value }.save!
    end
  end

  def vault_ref?(value)
    value.to_s.start_with?("vault:")
  end

  def secret_looking?(key)
    key.to_s.downcase.match?(/token|secret|key|password|credential/)
  end
end
