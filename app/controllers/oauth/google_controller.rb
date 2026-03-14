# frozen_string_literal: true

module OAuth
  class GoogleController < ApplicationController
    before_action :authenticate_user!

    def authorize
      client = GoogleWorkspace::OAuthClient.new

      unless client.configured?
        redirect_to integrations_path, alert: "Google OAuth not configured. Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET."
        return
      end

      state = SecureRandom.hex(32)
      session[:google_oauth_state] = state

      scopes = params[:scopes]&.map(&:to_sym) || GoogleWorkspace::OAuthClient::DEFAULT_SCOPES

      url = client.authorization_url(
        redirect_uri: oauth_google_callback_url,
        state: state,
        scopes: scopes
      )

      redirect_to url, allow_other_host: true
    end

    def callback
      if params[:error].present?
        redirect_to integrations_path, alert: "Google authorization denied: #{params[:error]}"
        return
      end

      unless params[:state] == session.delete(:google_oauth_state)
        redirect_to integrations_path, alert: "Invalid OAuth state. Please try again."
        return
      end

      client = GoogleWorkspace::OAuthClient.new
      result = client.exchange_code(
        code: params[:code],
        redirect_uri: oauth_google_callback_url
      )

      unless result.success?
        redirect_to integrations_path, alert: result.error
        return
      end

      # Fetch user info for display
      user_info = client.fetch_user_info(result.data[:access_token])
      email = user_info.success? ? user_info.data[:email] : nil

      GoogleWorkspace::CredentialBridge.store_tokens(
        access_token: result.data[:access_token],
        refresh_token: result.data[:refresh_token],
        expires_in: result.data[:expires_in],
        scope: result.data[:scope],
        email: email
      )

      redirect_to integrations_path, notice: "Google Workspace connected#{email ? " (#{email})" : ""}"
    end

    def disconnect
      GoogleWorkspace::CredentialBridge.disconnect!
      redirect_to integrations_path, notice: "Google Workspace disconnected"
    end
  end
end
