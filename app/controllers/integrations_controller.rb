# frozen_string_literal: true

class IntegrationsController < ApplicationController
  before_action :authenticate_user!

  def index
    @github_configured = VaultEntry.exists?(namespace: "github", key: "token")
    @gmail_configured = VaultEntry.exists?(namespace: "google", key: "gmail_address")
    @email_configured = VaultEntry.exists?(namespace: "email", key: "smtp_host")
    @jira_configured = VaultEntry.exists?(namespace: "jira", key: "base_url")
    @trello_configured = VaultEntry.exists?(namespace: "trello", key: "api_key")
    @telegram_configured = VaultEntry.exists?(namespace: "channel_credentials", key: "telegram_bot_token")
    @signal_configured = Channel.exists?(channel_type: "signal", enabled: true)
    @search_configured = Search::Resolver.configured?
    @search_provider = Search::Resolver.current_provider_name
    @remotes = CloudStorage::ConfigureRemote.list_remotes
    @backends = CloudStorage::ConfigureRemote::BACKENDS
    @mcp_servers = McpServer.order(:name)
    @mcp_presets = @mcp_servers.where(preset: true)
    @mcp_custom = @mcp_servers.where(preset: false)
    @agents = Agent.visible.order(:name)
  end

  def update_github
    token = params[:github_token].to_s.strip

    if token.present?
      store_vault("github", "token", token)

      redirect_to integrations_path, notice: "GitHub connected"
    else
      redirect_to integrations_path, alert: "Personal access token required"
    end
  end

  def test_github
    token = VaultEntry.find_by(namespace: "github", key: "token")&.value
    return render(json: { status: "error", message: "GitHub not configured" }, status: :unprocessable_entity) unless token

    uri = URI("https://api.github.com/user")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 5

    req = Net::HTTP::Get.new(uri)
    req["Authorization"] = "Bearer #{token}"
    req["Accept"] = "application/vnd.github+json"

    response = http.request(req)
    if response.is_a?(Net::HTTPSuccess)
      user = JSON.parse(response.body)
      render json: { status: "connected", user: user["login"], name: user["name"] }
    else
      render json: { status: "error", message: "HTTP #{response.code}" }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { status: "error", message: e.message }, status: :unprocessable_entity
  end

  def update_gmail
    address = params[:gmail_address].to_s.strip
    password = params[:gmail_app_password].to_s.strip

    if address.present? && password.present?
      store_vault("google", "gmail_address", address)
      store_vault("google", "gmail_app_password", password)
      redirect_to integrations_path, notice: "Gmail credentials saved"
    else
      redirect_to integrations_path, alert: "Email and app password required"
    end
  end

  def update_email
    host = params[:smtp_host].to_s.strip
    port = params[:smtp_port].to_s.strip.presence || "587"
    username = params[:smtp_username].to_s.strip
    password = params[:smtp_password].to_s.strip
    from_addr = params[:from_address].to_s.strip
    from_name = params[:from_name].to_s.strip

    if host.present? && username.present? && password.present?
      store_vault("email", "smtp_host", host)
      store_vault("email", "smtp_port", port)
      store_vault("email", "smtp_username", username)
      store_vault("email", "smtp_password", password)
      store_vault("email", "from_address", from_addr) if from_addr.present?
      store_vault("email", "from_name", from_name) if from_name.present?
      redirect_to integrations_path, notice: "SMTP credentials saved"
    else
      redirect_to integrations_path, alert: "Host, username, and password are required"
    end
  end

  def update_jira
    base_url = params[:jira_base_url].to_s.strip.chomp("/")
    email = params[:jira_email].to_s.strip
    token = params[:jira_api_token].to_s.strip

    if base_url.present? && email.present? && token.present?
      store_vault("jira", "base_url", base_url)
      store_vault("jira", "email", email)
      store_vault("jira", "api_token", token)
      redirect_to integrations_path, notice: "Jira credentials saved"
    else
      redirect_to integrations_path, alert: "All three Jira fields are required"
    end
  end

  def test_jira
    base_url = VaultEntry.find_by(namespace: "jira", key: "base_url")&.value
    email = VaultEntry.find_by(namespace: "jira", key: "email")&.value
    token = VaultEntry.find_by(namespace: "jira", key: "api_token")&.value

    return render(json: { status: "error", message: "Jira not configured" }, status: :unprocessable_entity) unless base_url

    uri = URI("#{base_url}/rest/api/3/myself")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 5

    req = Net::HTTP::Get.new(uri)
    req["Authorization"] = "Basic #{Base64.strict_encode64("#{email}:#{token}")}"
    req["Accept"] = "application/json"

    response = http.request(req)
    if response.is_a?(Net::HTTPSuccess)
      user = JSON.parse(response.body)
      render json: { status: "connected", user: user["displayName"], email: user["emailAddress"] }
    else
      render json: { status: "error", message: "HTTP #{response.code}" }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { status: "error", message: e.message }, status: :unprocessable_entity
  end

  def update_trello
    api_key = params[:trello_api_key].to_s.strip
    api_token = params[:trello_api_token].to_s.strip

    if api_key.present? && api_token.present?
      store_vault("trello", "api_key", api_key)
      store_vault("trello", "token", api_token)
      redirect_to integrations_path, notice: "Trello credentials saved"
    else
      redirect_to integrations_path, alert: "Both API Key and API Token are required"
    end
  end

  def test_trello
    api_key = VaultEntry.find_by(namespace: "trello", key: "api_key")&.value
    api_token = VaultEntry.find_by(namespace: "trello", key: "token")&.value

    return render(json: { status: "error", message: "Trello not configured" }, status: :unprocessable_entity) unless api_key

    uri = URI("https://api.trello.com/1/members/me?key=#{api_key}&token=#{api_token}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 5

    response = http.request(Net::HTTP::Get.new(uri))
    if response.is_a?(Net::HTTPSuccess)
      user = JSON.parse(response.body)
      render json: { status: "connected", user: user["fullName"], username: user["username"] }
    else
      render json: { status: "error", message: "HTTP #{response.code}" }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { status: "error", message: e.message }, status: :unprocessable_entity
  end

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
      redirect_to integrations_path, notice: "☁️ Remote '#{remote_name}' connected!"
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
    if server.stdio?
      result = Mcp::ProcessManager.new(server).start
    else
      result = Mcp::SseClient.discover_tools(server)
    end

    if result.success?
      redirect_to integrations_path, notice: "Connected to '#{server.name}'"
    else
      redirect_to integrations_path, alert: "Connection failed: #{result.error}"
    end
  end

  def disconnect_mcp_server
    server = McpServer.find(params[:id])
    if server.stdio?
      Mcp::ProcessManager.new(server).stop
    else
      server.mark_disconnected!
    end
    redirect_to integrations_path, notice: "Disconnected from '#{server.name}'"
  end

  def refresh_mcp_tools
    server = McpServer.find(params[:id])
    result = if server.stdio?
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

  # === Telegram ===

  def update_telegram
    token = params[:telegram_bot_token].to_s.strip
    if token.present?
      store_vault("channel_credentials", "telegram_bot_token", token)
      ch = Channel.find_or_initialize_by(channel_type: "telegram")
      ch.name ||= "Telegram Bot"
      ch.enabled = true
      webhook_secret = params[:telegram_webhook_secret].to_s.strip
      ch.config = (ch.config || {}).merge("webhook_secret" => webhook_secret) if webhook_secret.present?
      ch.save!
      redirect_to integrations_path, notice: "Telegram bot connected"
    else
      redirect_to integrations_path, alert: "Bot token is required"
    end
  end

  def test_telegram
    token = VaultEntry.find_by(namespace: "channel_credentials", key: "telegram_bot_token")&.value
    return render(json: { status: "error", message: "Telegram not configured" }, status: :unprocessable_entity) unless token
    uri = URI("https://api.telegram.org/bot\#{token}/getMe")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 5
    response = http.request(Net::HTTP::Get.new(uri))
    data = JSON.parse(response.body)
    if data["ok"]
      bot = data["result"]
      render json: { status: "connected", username: bot["username"], name: bot["first_name"] }
    else
      render json: { status: "error", message: data["description"] }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { status: "error", message: e.message }, status: :unprocessable_entity
  end

  # === Signal ===

  def update_signal
    phone = params[:signal_phone_number].to_s.strip
    api_url = params[:signal_api_url].to_s.strip.presence || "http://signal-cli:8080"
    if phone.present?
      ch = Channel.find_or_initialize_by(channel_type: "signal")
      ch.name ||= "Signal"
      ch.enabled = true
      ch.config = { "api_url" => api_url, "phone_number" => phone }
      ch.save!
      redirect_to integrations_path, notice: "Signal channel configured"
    else
      redirect_to integrations_path, alert: "Phone number is required"
    end
  end

  def test_signal
    ch = Channel.find_by(channel_type: "signal", enabled: true)
    return render(json: { status: "error", message: "Signal not configured" }, status: :unprocessable_entity) unless ch
    api_url = ch.config&.dig("api_url") || "http://signal-cli:8080"
    uri = URI("\#{api_url}/v1/about")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 5
    response = http.request(Net::HTTP::Get.new(uri))
    if response.is_a?(Net::HTTPSuccess)
      info = JSON.parse(response.body)
      render json: { status: "connected", version: info["versions"]&.first }
    else
      render json: { status: "error", message: "HTTP \#{response.code}" }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { status: "error", message: e.message }, status: :unprocessable_entity
  end

  private

  # GitHub CLI auth is handled lazily by the shell executor when agents need it

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
