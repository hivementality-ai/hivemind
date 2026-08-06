# frozen_string_literal: true

# Settings page for exposing this hivemind instance on a public URL so the
# desktop app can reach it. Admin/owner only — see the decision record in
# hivemind-desktop issues #10 and #2.
#
# Renders a wizard when unconfigured (path A: bring-your-own tunnel — verify
# a URL the admin already has; path B: guided Cloudflare — walk the three
# manual steps then automate the rest) and a status card once a canonical
# host is set.
class RemoteAccessController < ApplicationController
  before_action :authorize_admin_or_owner!

  def index
    @configured = RemoteAccess::ConfigStore.configured?
    @mode = RemoteAccess::ConfigStore.mode
    @canonical_host = RemoteAccess::ConfigStore.canonical_host
    @cloudflare_token_deep_link = Cloudflare::TunnelProvisioner.token_deep_link
    @connector_status = @mode == "cloudflare" ? RemoteAccess::ConnectorManager.status : nil
    @last_check_at = RemoteAccess::ConfigStore.last_check_at
    @http_ok = RemoteAccess::ConfigStore.http_ok?
    @websocket_ok = RemoteAccess::ConfigStore.websocket_ok?
    @last_error = RemoteAccess::ConfigStore.last_error
  end

  # Path A — bring-your-own tunnel. Verifies the admin's URL with a real
  # HTTP check + a `/cable` WebSocket handshake, then persists it as the
  # canonical host only if both pass.
  def verify_byo
    url = params[:public_url].to_s.strip

    result = RemoteAccess::HealthCheck.call(url)
    checks = result.payload || result.data

    if result.success?
      RemoteAccess::ConfigStore.canonical_host = url.chomp("/")
      RemoteAccess::ConfigStore.mode = "byo"
      RemoteAccess::ConfigStore.record_check_result(http_ok: true, websocket_ok: true)
      redirect_to remote_access_path, notice: "Remote access configured — #{url} is verified and set as your public URL."
    else
      @checks = checks
      @attempted_url = url
      flash.now[:alert] = "Verification failed: #{result.error}"
      render_wizard_with_error
    end
  end

  # Path B — guided Cloudflare. Provisions the tunnel + DNS via the
  # Cloudflare API, starts the managed cloudflared sidecar, health-checks
  # the resulting URL, then sets the canonical host.
  def provision_cloudflare
    api_token = params[:cloudflare_api_token].to_s.strip
    hostname = params[:hostname].to_s.strip

    if api_token.blank? || hostname.blank?
      flash.now[:alert] = "A Cloudflare API token and hostname are both required."
      return render_wizard_with_error
    end

    provisioner = Cloudflare::TunnelProvisioner.new(api_token: api_token, internal_port: internal_app_port)
    result = provisioner.provision(hostname: hostname)

    unless result.success?
      flash.now[:alert] = "Cloudflare setup failed: #{result.error}"
      return render_wizard_with_error
    end

    data = result.data
    RemoteAccess::ConfigStore.cloudflare_api_token = api_token
    RemoteAccess::ConfigStore.cloudflare_tunnel_token = data[:tunnel_token]
    RemoteAccess::ConfigStore.cloudflare_tunnel_id = data[:tunnel_id]
    RemoteAccess::ConfigStore.cloudflare_account_id = data[:account_id]
    RemoteAccess::ConfigStore.cloudflare_zone_id = data[:zone_id]

    write_tunnel_token_env(data[:tunnel_token])
    start_result = RemoteAccess::ConnectorManager.start

    unless start_result.success?
      flash.now[:alert] = "Tunnel created but the connector failed to start: #{start_result.error}. You can retry from the status card."
      @checks = nil
      @attempted_url = data[:public_url]
      return render_wizard_with_error
    end

    check = RemoteAccess::HealthCheck.call(data[:public_url])
    checks = check.payload || check.data
    RemoteAccess::ConfigStore.record_check_result(
      http_ok: checks&.dig(:http, :ok) || false,
      websocket_ok: checks&.dig(:websocket, :ok) || false,
      error: check.success? ? nil : check.error
    )

    RemoteAccess::ConfigStore.canonical_host = data[:public_url]
    RemoteAccess::ConfigStore.mode = "cloudflare"

    if check.success?
      redirect_to remote_access_path, notice: "Remote access configured via Cloudflare Tunnel — #{data[:public_url]} is live."
    else
      redirect_to remote_access_path, alert: "Tunnel provisioned, but the health check hasn't passed yet (#{check.error}). The connector may still be starting — try Re-verify shortly."
    end
  end

  # Re-runs the health check against the currently configured canonical host.
  def re_verify
    host = RemoteAccess::ConfigStore.canonical_host
    if host.blank?
      redirect_to remote_access_path, alert: "No public URL is configured yet." and return
    end

    result = RemoteAccess::HealthCheck.call(host)
    checks = result.payload || result.data
    RemoteAccess::ConfigStore.record_check_result(
      http_ok: checks&.dig(:http, :ok) || false,
      websocket_ok: checks&.dig(:websocket, :ok) || false,
      error: result.success? ? nil : result.error
    )

    if result.success?
      redirect_to remote_access_path, notice: "Verified — #{host} is reachable."
    else
      redirect_to remote_access_path, alert: "Verification failed: #{result.error}"
    end
  end

  # Restarts the managed cloudflared sidecar (Cloudflare path only).
  def restart_connector
    result = RemoteAccess::ConnectorManager.restart
    if result.success?
      redirect_to remote_access_path, notice: "Connector restarted."
    else
      redirect_to remote_access_path, alert: "Failed to restart connector: #{result.error}"
    end
  end

  # Clears configuration and returns to the wizard, without tearing down the
  # Cloudflare tunnel itself (the admin can delete it from their Cloudflare
  # dashboard, or reconfigure to reuse the same hostname).
  def reconfigure
    RemoteAccess::ConfigStore.clear!
    redirect_to remote_access_path, notice: "Remote access configuration cleared. Set it up again below."
  end

  # Disconnects: clears the canonical host and, for the managed path, stops
  # the connector sidecar.
  def disconnect
    RemoteAccess::ConnectorManager.stop if RemoteAccess::ConfigStore.mode == "cloudflare"
    RemoteAccess::ConfigStore.clear!
    redirect_to remote_access_path, notice: "Remote access disconnected."
  end

  private

  def render_wizard_with_error
    @configured = false
    @mode = RemoteAccess::ConfigStore.mode
    @canonical_host = RemoteAccess::ConfigStore.canonical_host
    @cloudflare_token_deep_link = Cloudflare::TunnelProvisioner.token_deep_link
    @connector_status = nil
    @last_check_at = RemoteAccess::ConfigStore.last_check_at
    @http_ok = RemoteAccess::ConfigStore.http_ok?
    @websocket_ok = RemoteAccess::ConfigStore.websocket_ok?
    @last_error = RemoteAccess::ConfigStore.last_error
    render :index, status: :unprocessable_entity
  end

  def internal_app_port
    ENV.fetch("APP_INTERNAL_PORT", 3000).to_i
  end

  # Writes/updates TUNNEL_TOKEN in the host .env so the cloudflared compose
  # service (which reads it via env_file) can start with `docker compose up`.
  def write_tunnel_token_env(token)
    env_path = File.join(RemoteAccess::ConnectorManager::HOST_DIR, ".env")
    return unless File.exist?(env_path)

    lines = File.readlines(env_path)
    found = false
    lines.map! do |line|
      if line.start_with?("TUNNEL_TOKEN=")
        found = true
        "TUNNEL_TOKEN=#{token}\n"
      else
        line
      end
    end
    lines << "TUNNEL_TOKEN=#{token}\n" unless found
    File.write(env_path, lines.join)
  rescue StandardError => e
    Rails.logger.warn("[RemoteAccess] Failed to write TUNNEL_TOKEN to .env: #{e.message}")
  end
end
