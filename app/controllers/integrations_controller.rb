# frozen_string_literal: true

class IntegrationsController < ApplicationController
  before_action :authenticate_user!

  def index
    @github_configured = VaultEntry.exists?(namespace: "github", key: "token")
    @gmail_configured = VaultEntry.exists?(namespace: "google", key: "gmail_address")
    @email_configured = VaultEntry.exists?(namespace: "email", key: "smtp_host")
    @jira_configured = VaultEntry.exists?(namespace: "jira", key: "base_url")
    @trello_configured = VaultEntry.exists?(namespace: "trello", key: "api_key")
    @gws_connected = GoogleWorkspace::CredentialBridge.configured?
    @gws_email = GoogleWorkspace::CredentialBridge.connected_email if @gws_connected
    @search_configured = Search::Resolver.configured?
    @search_provider = Search::Resolver.current_provider_name
    @embedding_provider = Embeddings::Registry.configured_provider
    @embedding_healthy = Memory::Embedding.available?
    @embedding_capabilities = begin
      Embeddings::Registry.current&.capabilities || {}
    rescue
      {}
    end
    @memory_count = MemoryEntry.count
    @embedded_count = MemoryEntry.where.not(embedding: nil).count
    @embedding_migration_active = Embeddings::Migration.active_migration.present?
    @gemini_key_configured = VaultEntry.exists?(namespace: "embedding", key: "google_ai_api_key")
    @remotes = CloudStorage::ConfigureRemote.list_remotes
    @backends = CloudStorage::ConfigureRemote::BACKENDS
    @mcp_servers = McpServer.order(:name)
    @mcp_presets = @mcp_servers.where(preset: true)
    @mcp_custom = @mcp_servers.where(preset: false)
    @agents = Agent.visible.order(:name)
  end

  # === Credential Updates ===

  def update_github
    save_credentials("github", { token: params[:github_token] }, required: %i[token], notice: "GitHub connected")
  end

  def update_gmail
    save_credentials("google", {
      gmail_address: params[:gmail_address],
      gmail_app_password: params[:gmail_app_password]
    }, required: %i[gmail_address gmail_app_password], notice: "Gmail credentials saved")
  end

  def update_email
    save_credentials("email", {
      smtp_host: params[:smtp_host],
      smtp_port: params[:smtp_port].to_s.strip.presence || "587",
      smtp_username: params[:smtp_username],
      smtp_password: params[:smtp_password],
      from_address: params[:from_address],
      from_name: params[:from_name]
    }, required: %i[smtp_host smtp_username smtp_password], notice: "SMTP credentials saved")
  end

  def update_jira
    save_credentials("jira", {
      base_url: params[:jira_base_url].to_s.strip.chomp("/"),
      email: params[:jira_email],
      api_token: params[:jira_api_token]
    }, required: %i[base_url email api_token], notice: "Jira credentials saved")
  end

  def update_trello
    save_credentials("trello", {
      api_key: params[:trello_api_key],
      token: params[:trello_api_token]
    }, required: %i[api_key token], notice: "Trello credentials saved")
  end

  def update_google_workspace
    json = if params[:gws_credentials_file].present?
      params[:gws_credentials_file].read
    else
      params[:gws_credentials_json].to_s.strip
    end

    if json.blank?
      redirect_to integrations_path, alert: "Paste your credentials JSON or upload the file"
      return
    end

    GoogleWorkspace::CredentialBridge.import_credentials(json)
    email = GoogleWorkspace::CredentialBridge.connected_email
    redirect_to integrations_path, notice: "Google Workspace connected#{email ? " (#{email})" : ""}"
  rescue JSON::ParserError
    redirect_to integrations_path, alert: "Invalid JSON — paste the output from `gws auth` exactly"
  rescue StandardError => e
    redirect_to integrations_path, alert: "Failed to import credentials: #{e.message}"
  end

  def update_embedding_key
    key = params[:gemini_embedding_api_key].to_s.strip
    if key.present?
      store_vault("embedding", "google_ai_api_key", key)
      redirect_to integrations_path, notice: "Gemini embedding API key saved"
    else
      redirect_to integrations_path, alert: "API key is required"
    end
  end

  # === Connection Tests ===

  def test_github
    render_test_result(Integrations::ConnectionTester.call(:github))
  end

  def test_jira
    render_test_result(Integrations::ConnectionTester.call(:jira))
  end

  def test_trello
    render_test_result(Integrations::ConnectionTester.call(:trello))
  end

  # === Cloud Storage ===

  def add_cloud_remote
    backend = params[:backend].to_s.strip
    remote_name = params[:remote_name].to_s.strip

    result = CloudStorage::ConfigureRemote.new(
      backend: backend,
      remote_name: remote_name,
      token: params[:token].to_s.strip.presence,
      params: cloud_params
    ).call

    if result[:success] != false
      redirect_to integrations_path, notice: "Remote '#{remote_name}' connected!"
    else
      redirect_to integrations_path, alert: result[:error]
    end
  end

  def remove_cloud_remote
    name = params[:remote_name].to_s.strip
    if CloudStorage::ConfigureRemote.delete_remote(name)
      redirect_to integrations_path, notice: "Remote '#{name}' removed"
    else
      redirect_to integrations_path, alert: "Failed to remove remote"
    end
  end

  def test_cloud_remote
    name = params[:remote_name].to_s.strip
    info = CloudStorage::ConfigureRemote.remote_info(name)

    if info
      render json: { status: "connected", info: info }
    else
      render json: { status: "error", message: "Could not connect to #{name}" }, status: :unprocessable_entity
    end
  end

  # === Search ===

  def update_search
    provider = params[:search_provider].to_s.strip
    api_key = params[:search_api_key].to_s.strip

    unless Search::Resolver::PROVIDERS.include?(provider)
      return redirect_to integrations_path, alert: "Invalid search provider"
    end

    store_vault("search", "provider", provider)

    if provider == "duckduckgo"
      VaultEntry.find_by(namespace: "search", key: "api_key")&.destroy
    elsif api_key.present?
      store_vault("search", "api_key", api_key)
    elsif !VaultEntry.exists?(namespace: "search", key: "api_key")
      return redirect_to integrations_path, alert: "API key required for #{provider.titleize}"
    end

    redirect_to integrations_path, notice: "Search provider updated to #{provider.titleize}"
  end

  def test_search
    provider = Search::Resolver.provider
    results = provider.search("test query", count: 2)

    if results.any?
      render json: {
        status: "connected",
        provider: provider.class.name.demodulize,
        results: results.size,
        first_result: results.first.title
      }
    else
      render json: { status: "error", message: "No results returned" }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { status: "error", message: e.message }, status: :unprocessable_entity
  end

  # === MCP Server Management ===

  def create_mcp_server
    server = McpServer.new(mcp_server_params)
    if server.save
      update_mcp_agent_assignments(server)
      redirect_to integrations_path, notice: "MCP server '#{server.name}' created"
    else
      redirect_to integrations_path, alert: server.errors.full_messages.join(", ")
    end
  end

  def update_mcp_server
    server = McpServer.find(params[:id])
    if server.update(mcp_server_params)
      update_mcp_agent_assignments(server)
      redirect_to integrations_path, notice: "MCP server '#{server.name}' updated"
    else
      redirect_to integrations_path, alert: server.errors.full_messages.join(", ")
    end
  end

  def destroy_mcp_server
    server = McpServer.find(params[:id])
    server.destroy
    redirect_to integrations_path, notice: "MCP server '#{server.name}' removed"
  end

  def connect_mcp_server
    server = McpServer.find(params[:id])
    result = server.stdio? ? Mcp::ProcessManager.new(server).start : Mcp::SseClient.discover_tools(server)

    if result.success?
      redirect_to integrations_path, notice: "Connected to '#{server.name}'"
    else
      redirect_to integrations_path, alert: "Connection failed: #{result.error}"
    end
  end

  def disconnect_mcp_server
    server = McpServer.find(params[:id])
    server.stdio? ? Mcp::ProcessManager.new(server).stop : server.mark_disconnected!
    redirect_to integrations_path, notice: "Disconnected from '#{server.name}'"
  end

  def refresh_mcp_tools
    server = McpServer.find(params[:id])
    result = server.stdio? ? Mcp::StdioClient.discover_tools(server) : Mcp::SseClient.discover_tools(server)

    if result.success?
      tools = result.data.is_a?(Hash) ? (result.data[:tools] || result.data["tools"] || []) : []
      redirect_to integrations_path, notice: "Refreshed #{tools.size} tools from '#{server.name}'"
    else
      redirect_to integrations_path, alert: "Refresh failed: #{result.error}"
    end
  end

  def toggle_mcp_server
    server = McpServer.find(params[:id])
    server.update!(enabled: !server.enabled)
    status = server.enabled? ? "enabled" : "disabled"
    redirect_to integrations_path, notice: "MCP server '#{server.name}' #{status}"
  end

  private

  def save_credentials(namespace, fields, required:, notice:)
    cleaned = fields.transform_values { |v| v.to_s.strip }
    result = Integrations::SaveCredentials.call(namespace: namespace, fields: cleaned, required: required)

    if result.success?
      redirect_to integrations_path, notice: notice
    else
      redirect_to integrations_path, alert: result.error
    end
  end

  def render_test_result(result)
    if result.success?
      render json: result.data
    else
      render json: { status: "error", message: result.error }, status: :unprocessable_entity
    end
  end

  def store_vault(namespace, key, value)
    entry = VaultEntry.find_or_initialize_by(namespace: namespace, key: key)
    entry.value = value
    entry.save!
  end

  def mcp_server_params
    permitted = params.require(:mcp_server).permit(:name, :transport, :command, :url, :npm_package, :icon, env_vars: {})
    if permitted[:env_vars].present?
      permitted[:env_vars].each do |key, value|
        if secret_looking?(key) && value.present? && !value.start_with?("vault:")
          namespace = "mcp_#{permitted[:name].parameterize(separator: "_")}"
          vault_key = key.downcase
          store_vault(namespace, vault_key, value)
          permitted[:env_vars][key] = "vault:#{namespace}/#{vault_key}"
        end
      end
    end
    permitted
  end

  def update_mcp_agent_assignments(server)
    agent_ids = params.dig(:mcp_server, :agent_ids)
    return unless agent_ids.is_a?(Array) || agent_ids.is_a?(ActionController::Parameters)

    server.agent_mcp_servers.destroy_all
    Array(agent_ids).reject(&:blank?).each do |agent_id|
      AgentMcpServer.create(agent: Agent.find(agent_id), mcp_server: server)
    end
  end

  def secret_looking?(key)
    key.to_s.downcase.match?(/token|secret|key|password|credential/)
  end

  def cloud_params
    params.permit(
      :provider, :access_key_id, :secret_access_key, :region, :endpoint,
      :account, :key, :host, :user, :port, :pass, :key_file
    ).to_h.symbolize_keys
  end
end
