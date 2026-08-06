# frozen_string_literal: true

class IntegrationsController < ApplicationController
  before_action :authenticate_user!

  def index
    @github_configured = VaultEntry.exists?(namespace: "github", key: "token")
    @gmail_configured = VaultEntry.exists?(namespace: "google", key: "gmail_address")
    @email_configured = VaultEntry.exists?(namespace: "email", key: "smtp_host")
    @jira_configured = VaultEntry.exists?(namespace: "jira", key: "base_url")
    @trello_configured = VaultEntry.exists?(namespace: "trello", key: "api_key")
    @gws_oauth_configured = GoogleWorkspace::OAuthClient.new.configured?
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
    @pipedream_configured = Pipedream::TokenManager.new.configured?
    @pipedream_environment = Setting.get("pipedream_environment") || "development"
    @pipedream_project_id = Setting.get("pipedream_project_id")
    @pipedream_servers = @mcp_servers.select { |s| s.metadata.to_h["provider"] == "pipedream" }
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
    client_id = params[:google_client_id].to_s.strip
    client_secret = params[:google_client_secret].to_s.strip

    if client_id.blank? || client_secret.blank?
      redirect_to integrations_path, alert: "Both Client ID and Client Secret are required"
      return
    end

    store_vault("google_workspace", "client_id", client_id)
    store_vault("google_workspace", "client_secret", client_secret)

    redirect_to integrations_path, notice: "Google Workspace credentials saved. Click \"Connect Google Account\" to authorize."
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
    result = if pipedream_server?(server)
      Mcp::PipedreamClient.discover_tools(server)
    elsif server.stdio?
      Mcp::ProcessManager.new(server).start
    else
      Mcp::SseClient.discover_tools(server)
    end

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
    result = if pipedream_server?(server)
      Mcp::PipedreamClient.discover_tools(server)
    elsif server.stdio?
      Mcp::StdioClient.discover_tools(server)
    else
      Mcp::SseClient.discover_tools(server)
    end

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

  # === Pipedream Connect ===

  def update_pipedream
    project_id = params[:pipedream_project_id].to_s.strip
    if project_id.blank? || params[:pipedream_client_id].to_s.strip.blank? || params[:pipedream_client_secret].to_s.strip.blank?
      return redirect_to integrations_path, alert: "Client ID, Client Secret, and Project ID are all required"
    end

    store_vault("pipedream", "client_id", params[:pipedream_client_id].to_s.strip)
    store_vault("pipedream", "client_secret", params[:pipedream_client_secret].to_s.strip)
    Setting.set("pipedream_project_id", project_id)
    Setting.set("pipedream_environment", params[:pipedream_environment].to_s.strip.presence || "development")
    Setting.set("pipedream_external_user_id", pipedream_external_user_id)
    Pipedream::TokenManager.new.refresh_access_token!

    redirect_to integrations_path, notice: "Pipedream connected. Enable the apps you want your agents to use."
  end

  # Creates the McpServer row for an app, then sends the admin to Pipedream's hosted Connect Link to
  # authorize the account. On return, #pipedream_callback discovers the app's tools.
  def enable_pipedream_app
    slug = params[:app_slug].to_s.strip.downcase
    return redirect_to integrations_path, alert: "App slug is required" if slug.blank?

    tokens = Pipedream::TokenManager.new
    return redirect_to integrations_path, alert: "Configure Pipedream first" unless tokens.configured?

    server = McpServer.find_or_initialize_by(name: "Pipedream: #{slug}")
    server.update!(
      transport: "sse",
      url: Mcp::PipedreamClient::REMOTE_MCP_URL,
      preset: false,
      metadata: { "provider" => "pipedream", "app_slug" => slug, "external_user_id" => pipedream_external_user_id }
    )

    result = tokens.mint_connect_token(
      external_user_id: pipedream_external_user_id,
      app_slug: slug,
      success_redirect_uri: pipedream_callback_url(server_id: server.id),
      error_redirect_uri: integrations_url
    )

    if result.success?
      redirect_to result.data[:connect_url], allow_other_host: true
    else
      redirect_to integrations_path, alert: "Could not start Pipedream connection: #{result.error}"
    end
  end

  def pipedream_callback
    server = McpServer.find_by(id: params[:server_id])
    return redirect_to integrations_path, alert: "Unknown Pipedream app" unless server

    result = Mcp::PipedreamClient.discover_tools(server)
    if result.success?
      count = result.data[:tools]&.size || 0
      redirect_to integrations_path, notice: "Connected #{server.name} — #{count} tools available"
    else
      redirect_to integrations_path, alert: "Connected the account, but tool discovery failed: #{result.error}"
    end
  end

  private

  def pipedream_server?(server)
    server.metadata.to_h["provider"] == "pipedream"
  end

  # Stable per-install identifier sent to Pipedream as x-pd-external-user-id.
  def pipedream_external_user_id
    @pipedream_external_user_id ||= begin
      existing = Setting.get("pipedream_external_user_id").presence
      existing || SecureRandom.uuid.tap { |id| Setting.set("pipedream_external_user_id", id) }
    end
  end

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
