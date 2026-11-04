# frozen_string_literal: true

class ApiController < ApplicationController
  skip_before_action :verify_authenticity_token
  # Bearer ApiTokens are the credential for this whole namespace — headless
  # clients (e.g. the desktop app) never hold a Devise session cookie, so the
  # inherited session-based authenticate_user! must not gate these actions.
  skip_before_action :authenticate_user!
  before_action :authenticate_api_token

  rescue_from ActiveRecord::RecordNotFound do |e|
    render json: { error: "Not found" }, status: :not_found
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def authenticate_api_token
    token = request.headers["Authorization"]&.gsub(/^Bearer /, "")

    return render json: { error: "Unauthorized" }, status: :unauthorized unless token

    @current_api_token = ApiToken.authenticate(token)

    return render json: { error: "Unauthorized" }, status: :unauthorized unless @current_api_token

    @current_api_token.touch_last_used!
  end

  def current_api_token
    @current_api_token
  end

  # Overrides Devise's session-based current_user so downstream code (e.g.
  # `current_user.id` when creating records) resolves to the token's owner.
  def current_user
    @current_api_token&.user
  end
end
