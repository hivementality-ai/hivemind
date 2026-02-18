# frozen_string_literal: true

class OauthCallbacksController < ApplicationController
  before_action :authenticate_user!

  # GET /auth/google/authorize
  # Redirects user to Google's consent screen
  def google_authorize
    remote_name = params[:remote_name].to_s.strip.presence || "gdrive"
    session[:oauth_remote_name] = remote_name

    client_id = google_credentials[:client_id]
    redirect_uri = google_redirect_uri

    unless client_id.present?
      redirect_to integrations_path, alert: "Google OAuth not configured. Add client_id and client_secret in settings."
      return
    end

    auth_url = "https://accounts.google.com/o/oauth2/v2/auth?" + {
      client_id: client_id,
      redirect_uri: redirect_uri,
      response_type: "code",
      scope: "https://www.googleapis.com/auth/drive",
      access_type: "offline",
      prompt: "consent",
      state: form_authenticity_token
    }.to_query

    redirect_to auth_url, allow_other_host: true
  end

  # GET /auth/google/callback
  # Google redirects here after user authorizes
  def google_callback
    code = params[:code]

    if code.blank?
      redirect_to integrations_path, alert: "Authorization failed: #{params[:error] || 'no code returned'}"
      return
    end

    # Exchange auth code for tokens
    token_response = exchange_google_code(code)

    unless token_response[:success]
      redirect_to integrations_path, alert: "Failed to get token: #{token_response[:error]}"
      return
    end

    # Build rclone token JSON
    rclone_token = {
      access_token: token_response[:access_token],
      token_type: "Bearer",
      refresh_token: token_response[:refresh_token],
      expiry: token_response[:expiry]
    }.to_json

    # Configure rclone remote
    remote_name = session.delete(:oauth_remote_name) || "gdrive"

    result = CloudStorage::ConfigureRemote.new(
      backend: "drive",
      remote_name: remote_name,
      token: rclone_token
    ).call

    if result[:success]
      redirect_to integrations_path, notice: "Google Drive connected as '#{remote_name}' ✅"
    else
      redirect_to integrations_path, alert: "Connected to Google but failed to configure storage: #{result[:error]}"
    end
  end

  private

  def exchange_google_code(code)
    uri = URI("https://oauth2.googleapis.com/token")
    response = Net::HTTP.post_form(uri, {
      code: code,
      client_id: google_credentials[:client_id],
      client_secret: google_credentials[:client_secret],
      redirect_uri: google_redirect_uri,
      grant_type: "authorization_code"
    })

    data = JSON.parse(response.body)

    if data["access_token"]
      {
        success: true,
        access_token: data["access_token"],
        refresh_token: data["refresh_token"],
        expiry: data["expires_in"] ? (Time.current + data["expires_in"].to_i).iso8601 : nil
      }
    else
      { success: false, error: data["error_description"] || data["error"] || "Unknown error" }
    end
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def google_credentials
    @google_credentials ||= begin
      config = ProviderConfig.find_by(adapter_type: "google")&.config || {}
      {
        client_id: config["client_id"].presence || ENV["GOOGLE_CLIENT_ID"],
        client_secret: config["client_secret"].presence || ENV["GOOGLE_CLIENT_SECRET"]
      }
    end
  end

  def google_redirect_uri
    "#{request.base_url}/auth/google/callback"
  end
end
