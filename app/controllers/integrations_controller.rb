# frozen_string_literal: true

class IntegrationsController < ApplicationController
  before_action :authenticate_user!

  def index
    @github_configured = VaultEntry.exists?(namespace: "github", key: "token")
    @gmail_configured = VaultEntry.exists?(namespace: "google", key: "gmail_address")
    @email_configured = VaultEntry.exists?(namespace: "email", key: "smtp_host")
    @jira_configured = VaultEntry.exists?(namespace: "jira", key: "base_url")
    @search_configured = Search::Resolver.configured?
    @search_provider = Search::Resolver.current_provider_name
    @remotes = CloudStorage::ConfigureRemote.list_remotes
    @backends = CloudStorage::ConfigureRemote::BACKENDS
    @google_oauth_available = google_oauth_configured?
  end

  def update_github
    token = params[:github_token].to_s.strip

    if token.present?
      store_vault("github", "token", token)

      # Configure gh CLI in workspace container
      configure_github_cli(token)

      redirect_to integrations_path, notice: "GitHub connected — gh CLI configured in workspace"
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

  def update_google_oauth
    client_id = params[:google_client_id].to_s.strip
    client_secret = params[:google_client_secret].to_s.strip

    if client_id.present? && client_secret.present?
      store_vault("google", "client_id", client_id)
      store_vault("google", "client_secret", client_secret)
      redirect_to integrations_path, notice: "Google OAuth credentials saved ✅"
    else
      redirect_to integrations_path, alert: "Both Client ID and Client Secret are required"
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

  private

  def google_oauth_configured?
    # Check vault first, then ProviderConfig, then env
    return true if VaultEntry.exists?(namespace: "google", key: "client_id", agent_id: nil)

    config = ProviderConfig.find_by(adapter_type: "google")
    return true if config&.config&.dig("client_id").present?

    ENV["GOOGLE_CLIENT_ID"].present?
  rescue ActiveRecord::Encryption::Errors::Configuration
    ENV["GOOGLE_CLIENT_ID"].present?
  end

  def configure_github_cli(token)
    # Write token to workspace volume so gh CLI can use it
    auth_dir = "/workspace/.hivemind/github"
    FileUtils.mkdir_p(auth_dir)
    File.write("#{auth_dir}/token", token)
    File.chmod(0o600, "#{auth_dir}/token")

    # Configure gh in workspace container via docker exec
    begin
      require "open3"
      Open3.capture3(
        "docker", "exec", "hivemind-workspace-1",
        "bash", "-c",
        "echo '#{token}' | gh auth login --with-token 2>/dev/null || true"
      )
    rescue StandardError => e
      Rails.logger.warn("GitHub CLI setup in workspace failed: #{e.message}")
    end
  end

  def store_vault(namespace, key, value)
    entry = VaultEntry.find_or_initialize_by(namespace: namespace, key: key)
    entry.value = value
    entry.save!
  end

  def cloud_params
    params.permit(
      :provider, :access_key_id, :secret_access_key, :region, :endpoint,
      :account, :key, :host, :user, :port, :pass, :key_file
    ).to_h.symbolize_keys
  end
end
