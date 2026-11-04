# frozen_string_literal: true

# Browser-side leg of the desktop companion app pairing flow (RFC 8252
# loopback pattern). `new`/`create`/`deny` are Devise-session-protected pages
# where a logged-in user approves or denies a pairing request initiated by
# the desktop app. `exchange` is the unauthenticated JSON endpoint the
# desktop app calls directly (no browser session) to trade the one-time code
# it received on the loopback redirect for a real ApiToken.
class DesktopPairingController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :exchange ]
  skip_before_action :verify_authenticity_token, only: [ :exchange ]

  MIN_PORT = 1
  MAX_PORT = 65_535

  # GET /desktop_pairing/authorize
  def new
    @device_name = params[:device_name].presence || "Desktop pairing"
    @code_challenge = params[:code_challenge]
    @state = params[:state]
    @port = params[:port]

    render plain: "Invalid pairing request", status: :bad_request unless valid_pairing_request?
  end

  # POST /desktop_pairing/authorize
  def create
    unless valid_pairing_request?
      return render plain: "Invalid pairing request", status: :bad_request
    end

    pairing_code = current_user.desktop_pairing_codes.create!(
      device_name: params[:device_name].presence || "Desktop pairing",
      code_challenge: params[:code_challenge]
    )

    redirect_to loopback_callback_url(code: pairing_code.code, state: params[:state]), allow_other_host: true
  end

  # POST /desktop_pairing/deny
  def deny
    unless valid_port?(params[:port])
      return render plain: "Invalid pairing request", status: :bad_request
    end

    redirect_to loopback_callback_url(error: "access_denied", state: params[:state]), allow_other_host: true
  end

  # POST /desktop_pairing/exchange
  def exchange
    pairing_code = DesktopPairingCode.exchange!(code: params[:code], code_verifier: params[:code_verifier])

    unless pairing_code
      return render json: { error: "invalid_grant" }, status: :unprocessable_entity
    end

    token = pairing_code.user.api_tokens.create!(name: pairing_code.device_name)

    render json: { token: token.raw_token, device_name: token.name }, status: :ok
  end

  private

  def valid_pairing_request?
    params[:code_challenge].present? && params[:state].present? && valid_port?(params[:port])
  end

  def valid_port?(port)
    port.to_s.match?(/\A\d{1,5}\z/) && port.to_i.between?(MIN_PORT, MAX_PORT)
  end

  # Always targets 127.0.0.1 — the port is the only attacker/desktop-controlled
  # piece of the redirect target, so this can never redirect off-loopback.
  def loopback_callback_url(query)
    uri = URI::HTTP.build(host: "127.0.0.1", port: params[:port].to_i, path: "/callback")
    uri.query = query.compact.to_query
    uri.to_s
  end
end
